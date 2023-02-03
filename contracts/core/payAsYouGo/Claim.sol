// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/// @title Insurance Claim Governance Contract
/// @author Anshik Bansal <anshik@safezen.finance>

// Importing contracts
import "./../../BaseUpgradeablePausable.sol";

/// Importing required libraries
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

// Importing interfaces
import "./../../interfaces/IClaim.sol";
import "./../../interfaces/IGlobalPauseOperation.sol";
import "@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol";


/// Report any bug or issues at:
/// @custom:security-contact anshik@safezen.finance

contract ClaimGovernance is IClaim, BaseUpgradeablePausable {
    /// claimID: unique insurance claim ID
    /// _openClaimsCount: count of the open insurance claims
    /// VOTING_END_TIME: voting maximum duration in hours
    /// TIME_BEFORE_VOTING_START: time before voting starts, so as users can be notified
    /// AFTER_VOTING_WAIT_PERIOD: voting challenge duration
    uint256 public claimID;
    uint256 private _stakedAmount;
    uint256 private _openClaimsCount;
    uint256 private constant VOTING_END_TIME = 5 minutes;
    uint256 private constant TIME_BEFORE_VOTING_START = 1 minutes;
    uint256 private constant AFTER_VOTING_WAIT_PERIOD = 1 minutes;
    
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeERC20Upgradeable for IERC20PermitUpgradeable;

    /// _tokenGSZT: SafeZen Governance contract
    /// _globalPauseOperation: Pause Operation contract
    IERC20Upgradeable private _tokenDAI;
    IERC20PermitUpgradeable private _tokenPermitDAI;
    IERC20Upgradeable private _tokenGSZT;
    IGlobalPauseOperation private _globalPauseOperation;

    /// @dev collects essential insurance claim info
    /// @param claimer: claimer wallet address
    /// @param _claimID: unique insurance claim ID
    /// @param subcategoryID: insurance sub-category, e.g., USDC depeg coverage, DAI depeg coverage.
    /// @param claimAmountRequested: claim amount requested by claimer.
    /// @param proof: digital uploaded proof of the claiming event 
    /// @param closed: checks if the insurance claim is closed or not.
    /// @param accepted: checks if the insurance claim request has been accpeted or not.
    /// @param isChallenged: checks if the insurance claim has been challenged or not.
    /// @param votingInfo: maps insurance claim ID to VotingInfo
    /// @param receipts:
    struct Claim {
        address claimer;
        uint256 _claimID;  // not needed thou, but nice to have
        uint256 categoryID; 
        uint256 subcategoryID;
        uint256 claimAmountRequested;
        string proof;  // IPFS link or some storage link, where proof is stored
        bool closed;
        bool accepted;
        bool isChallenged;
        mapping(uint256 => VotingInfo) votingInfo; 
        mapping(address => Receipt) receipts;
    }

    struct VotingInfo {
        uint256 votingStartTime;
        uint256 votingEndTime;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 advisorForVotes;
        uint256 advisorAgainstVotes;
        uint256 votingCounts;  // no of times decision has been challenged
    }

    struct Receipt {
        bool hasVoted;
        bool support;
        uint256 votes;
    }

    mapping(address => bool) public isAdvisor;

    /// @notice The official record of all claims ever made
    mapping(uint256 => Claim) public claims;

    /// @notice The latest claim for each individual claimer
    /// if a user have filed most claims, then the protocol that user invests are generally risky
    mapping(address => uint256) public individualClaims;

    /// @notice mapping the protocol specific claims count to date
    /// more the number, more the risky the platform will be
    mapping(uint256 => mapping(uint256 => uint256)) public protocolSpecificClaims;

    /// @custom:oz-upgrades-unsafe-allow-constructor
    constructor(address tokenDAI) {
        _tokenDAI = IERC20Upgradeable(tokenDAI); // Immutable
        _tokenPermitDAI = IERC20PermitUpgradeable(tokenDAI); //Immutable
    }

    function initialize(
        address safezenGovernanceTokenAddress,
        address globalPauseOperationAddress
    ) external initializer {
        _stakedAmount = 10e18;
        _tokenGSZT = IERC20Upgradeable(safezenGovernanceTokenAddress);
        _globalPauseOperation = IGlobalPauseOperation(globalPauseOperationAddress);
        __BaseUpgradeablePausable_init(_msgSender());
    }

    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }

    /// @dev in case if certain claim require additional time for DAO, 
    /// for e.g., awaiting additional inputs to reserve their decisions 
    function updateVotingEndTime(
        uint256 _claimID, 
        uint256 timeInHours
    ) external onlyAdmin {
        claims[_claimID].votingInfo[_claimID].votingEndTime = timeInHours * 1 hours;
    }

    function updateAdvisors(address userAddress) external onlyAdmin {
        isAdvisor[userAddress] = true;
    }

    function updateStakeAmount(uint256 stakeAmount) external onlyAdmin {
        _stakedAmount = stakeAmount;
    }

    function createClaim(
        uint256 categoryID,
        uint256 subcategoryID, 
        string memory proof, 
        uint256 requestedClaimAmount,
        uint256 deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) public override returns(bool) {
        ++claimID;
        Claim storage newClaim = claims[claimID];
        newClaim.categoryID = categoryID;
        newClaim.subcategoryID = subcategoryID;
        newClaim._claimID = claimID;
        newClaim.claimer = _msgSender();
        newClaim.proof = proof;
        newClaim.claimAmountRequested = requestedClaimAmount;
        newClaim.votingInfo[claimID].votingStartTime = block.timestamp + TIME_BEFORE_VOTING_START;
        newClaim.votingInfo[claimID].votingEndTime = newClaim.votingInfo[claimID].votingStartTime + VOTING_END_TIME;
        ++individualClaims[_msgSender()];
        ++protocolSpecificClaims[categoryID][subcategoryID];
        ++_openClaimsCount;
        bool success = _globalPauseOperation.pauseOperation();
        if(!success) {
            revert Claim__PausedOperationFailedError();
        }
        _tokenPermitDAI.safePermit(_msgSender(), address(this), _stakedAmount, deadline, v, r, s);
        _tokenDAI.safeTransfer(address(this), _stakedAmount);
        emit NewClaimCreated(_msgSender(), claimID, proof);
        return true;
    }
     
    
    function vote(
        uint256 _claimID, 
        bool support
    ) external override returns(bool) {
        /// checks are made in order
        /// 1. making sure voting time has started
        /// 2. has the user voted or not
        /// 3. if not, whether the user is voting within the voting time limit
        if (claims[_claimID].votingInfo[_claimID].votingStartTime > block.timestamp) {
            revert Claim__VotingNotYetStartedError();
        }
        if (claims[_claimID].receipts[_msgSender()].hasVoted) {
            revert Claim__UserAlreadyVotedError();
        }
        if (claims[_claimID].votingInfo[_claimID].votingEndTime < block.timestamp) {
            revert Claim__VotingTimeEndedError();
        }
        claims[_claimID].receipts[_msgSender()].support = support;
        claims[_claimID].receipts[_msgSender()].votes = _tokenGSZT.balanceOf(_msgSender());
        claims[_claimID].receipts[_msgSender()].hasVoted = true;

        if ((isAdvisor[_msgSender()]) && (claims[_claimID].votingInfo[_claimID].votingCounts == 2)) {
            if (support) {
                claims[_claimID].votingInfo[_claimID].advisorForVotes += claims[_claimID].receipts[_msgSender()].votes;
            }
            else {
                claims[_claimID].votingInfo[_claimID].advisorAgainstVotes += claims[_claimID].receipts[_msgSender()].votes;
            }
        }
        else {
            if (support) {
                claims[_claimID].votingInfo[_claimID].forVotes += claims[_claimID].receipts[_msgSender()].votes;
            }
            else {
                claims[_claimID].votingInfo[_claimID].againstVotes += claims[_claimID].receipts[_msgSender()].votes;
            }
        }
        return true;
    }

    /// @dev this function aims to finalize the claim decision, based on the claim voting
    /// @param _claimID: unique insurance claim ID
    function claimDecision(uint256 _claimID) external override returns(bool) {
        if (
            (claims[_claimID].votingInfo[_claimID].votingEndTime + AFTER_VOTING_WAIT_PERIOD) > 
            block.timestamp
        ) {
            revert Claim__VotingDecisionNotYetFinalizedError();
        }
        if (claims[_claimID].isChallenged) {
            revert Claim__DecisionChallengedError();
        }
        uint256 totalCommunityVotes = (
            claims[_claimID].votingInfo[_claimID].forVotes + 
            claims[_claimID].votingInfo[_claimID].againstVotes
        );
        if (claims[_claimID].votingInfo[_claimID].votingCounts == 2) {
            uint256 totalAdvisorVotes = (
                claims[_claimID].votingInfo[_claimID].advisorForVotes + 
                claims[_claimID].votingInfo[_claimID].advisorAgainstVotes
            );
            uint256 forAdvisorVotesEligible = (
                (claims[_claimID].votingInfo[_claimID].advisorForVotes >= 
                claims[_claimID].votingInfo[_claimID].advisorAgainstVotes) ? 
                ((claims[claimID].votingInfo[claimID].forVotes * 100) / totalAdvisorVotes) : 0
            );
            /// even if all the community votes are in favor, but, 49% of the voting power will be 
            /// given to the advisors in the final claim decision round.
            /// Community --> (100 * 0.51) = 51%    Advisors -->  (60 * 0.49) = 29.4%
            /// Total  = 51% + 29.4% < 80% (needed to get approved)
            /// keeping >= 59% instead of 60% because of underflow value in forAdvisorVotesEligible
            if (forAdvisorVotesEligible >= 59) {
                uint256 forVotesEligible = (
                    (claims[_claimID].votingInfo[_claimID].forVotes > 
                    claims[_claimID].votingInfo[_claimID].againstVotes) ? 
                    ((claims[_claimID].votingInfo[_claimID].forVotes * 100) / totalCommunityVotes) : 1
                );
                uint256 supportPercent = (
                    ((forAdvisorVotesEligible * 49) / 100) + 
                    ((forVotesEligible * 51) / 100)
                );
                claims[_claimID].accepted = (supportPercent >= 80) ? true : false;
            }
            else {
                claims[_claimID].accepted = false;
            }
        }
        else {
            uint256 forVotesEligible = (
                (claims[_claimID].votingInfo[_claimID].forVotes > 
                claims[_claimID].votingInfo[_claimID].againstVotes) ? 
                ((claims[_claimID].votingInfo[_claimID].forVotes * 100) / totalCommunityVotes) : 1
            );
            claims[_claimID].accepted = (forVotesEligible >= 80) ? true : false;
        }
        claims[_claimID].closed = true;
        if (claims[_claimID].accepted) {
            uint256 totalAmountStaked = (
                _stakedAmount * (claims[_claimID].votingInfo[_claimID].votingCounts + 1)
            );
            _tokenDAI.safeTransfer(claims[_claimID].claimer, totalAmountStaked);
        }
        --_openClaimsCount;
        return true;
    }

    
    function challengeDecision(
        uint256 _claimID,
        uint256 deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external override {
        if ((!claims[_claimID].closed) || (!claims[_claimID].isChallenged)) {
            revert Claim__DecisionNotYetTakenError();
        }
        if (claims[_claimID].votingInfo[_claimID].votingCounts >= 2) {
            revert Claim__DecisionNoLongerCanBeChallengedError();
        }
        claims[_claimID].isChallenged = true;
        ++claims[claimID].votingInfo[claimID + 1].votingCounts; 
        createClaim(
            claims[_claimID].categoryID,
            claims[_claimID].subcategoryID,
            claims[_claimID].proof,
            claims[_claimID].claimAmountRequested,
            deadline, 
            v, 
            r, 
            s
        );
        
        // ^ global _claimID, as the latest claim refers to challenged claim
    }

    function viewVoteReceipt(
        uint256 _claimID
    ) external view override returns(bool, bool, uint256) {
        return (
            claims[_claimID].receipts[_msgSender()].hasVoted,
            claims[_claimID].receipts[_msgSender()].support,
            claims[_claimID].receipts[_msgSender()].votes
        );
    }

    function getClaimID() external view override returns(uint256) {
        return claimID;
    }

    function getVotingInfo(
        uint256 _claimID
    ) external view override returns(
        uint256, uint256, uint256, uint256, uint256, uint256, uint256
    ) {
        VotingInfo storage claim = claims[_claimID].votingInfo[_claimID];
        return (
            claim.votingStartTime, 
            claim.votingEndTime, 
            claim.forVotes, 
            claim.againstVotes, 
            claim.advisorForVotes, 
            claim.advisorAgainstVotes, 
            claim.votingCounts
        );
    }
}