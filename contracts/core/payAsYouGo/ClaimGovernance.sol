// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/// @title Insurance Claim Governance Contract
/// @author Anshik Bansal <anshik@safezen.finance>

// Importing contracts
import "./../../BaseUpgradeablePausable.sol";

/// Importing required libraries
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

// Importing interfaces
import "./../../interfaces/IClaimGovernance.sol";
import "./../../interfaces/IInsuranceRegistry.sol";
import "./../../interfaces/IGlobalPauseOperation.sol";


/// Report any bug or issues at:
/// @custom:security-contact anshik@safezen.finance

contract ClaimGovernance is IClaimGovernance, BaseUpgradeablePausable {
    /// _claimID: unique insurance claim ID
    /// _stakedAmount: stake amount to register the claim
    /// _openClaimsCount: count of the open insurance claims
    /// VOTING_END_TIME: voting maximum duration in hours
    /// TIME_BEFORE_VOTING_START: time before voting starts, so as users can be notified
    /// AFTER_VOTING_WAIT_PERIOD: voting challenge duration
    uint256 private _claimID;
    uint256 private _stakedAmount;
    uint256 private _openClaimsCount;
    uint256 private constant VOTING_END_TIME = 5 minutes;
    uint256 private constant TIME_BEFORE_VOTING_START = 1 minutes;
    uint256 private constant AFTER_VOTING_WAIT_PERIOD = 1 minutes;
    
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeERC20Upgradeable for IERC20PermitUpgradeable;

    /// _tokenDAI: DAI ERC20 token interface
    /// _tokenPermitDAI: DAI ERC20 token interface with permit
    /// _tokenGSZT: SafeZen Governance contract interface
    /// _insuranceRegistry: Insurance Registry contract interface
    /// _globalPauseOperation: Global Pause Operation contract interface
    IERC20Upgradeable private immutable _tokenDAI;
    IERC20PermitUpgradeable private immutable _tokenPermitDAI;
    IERC20Upgradeable private _tokenGSZT;
    IInsuranceRegistry private _insuranceRegistry;
    IGlobalPauseOperation private _globalPauseOperation;

    /// @dev collects essential insurance claim info
    /// claimer: claimer wallet address
    /// claimID: unique insurance claim ID
    /// subcategoryID: insurance sub-category, e.g., USDC depeg coverage, DAI depeg coverage.
    /// claimAmountRequested: claim amount requested by claimer.
    /// proof: digital uploaded proof of the claiming event 
    /// closed: checks if the insurance claim is closed or not.
    /// accepted: checks if the insurance claim request has been accpeted or not.
    /// isChallenged: checks if the insurance claim has been challenged or not.
    /// votingInfo: maps:: claimID(uint256) => VotingInfo(struct)
    /// receipts: maps:: _msgSender()(address) => Receipt(struct)
    struct Claim {
        address claimer;
        uint256 claimID;  // not needed thou, but nice to have
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

    /// @notice collects essential claim voting info
    /// votingStartTime: claim voting start time
    /// votingEndTime: claim voting end time
    /// forVotes: votes in favor of the registered claim
    /// againstVotes: votes in against of the registered claim
    /// advisorsForVotes: advisor votes in favor of the registered claim
    /// advisorAgainstVotes: advisor votes in against of the registered claim 
    /// challengedCounts: number of times the voting decision has been challenged
    struct VotingInfo {
        uint256 votingStartTime;
        uint256 votingEndTime;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 advisorForVotes;
        uint256 advisorAgainstVotes;
        uint256 challengedCounts;
    }

    /// @notice collects user voting info for a particular claim
    /// hasVoted: checks whether the user has voted or not
    /// support: checks whether the user has cast votes in favor of the particular claim or not
    /// votes: the voting power of the user, based on GSZT token user owns
    struct Receipt {
        bool hasVoted;
        bool support;
        uint256 votes;
    }

    /// Maps :: userAddress(address) => isAdvisor(bool)
    mapping(address => bool) public isAdvisor;

    /// Maps :: claimID(uint256) => Claim(struct)
    mapping(uint256 => Claim) public claims;

    /// Maps :: userAddress(uint256) => individualClaims(uint256)
    /// @notice stores user claim history, i.e.,
    /// if a user have filed most claims, then user investments are generally risky.
    mapping(address => uint256) public individualClaims;

    /// Maps :: categoryID(uint256) => subCategoryID(uint256) => productSpecificClaims
    /// @notice mapping the insurance product specific claims count to date.
    /// the higher the number, more the risky the platform will be.
    mapping(uint256 => mapping(uint256 => uint256)) public productSpecificClaims;

    /// @custom:oz-upgrades-unsafe-allow-constructor
    constructor(address tokenDAI) {
        _tokenDAI = IERC20Upgradeable(tokenDAI); // Immutable
        _tokenPermitDAI = IERC20PermitUpgradeable(tokenDAI); //Immutable
    }

    function initialize(
        address addressGSZT,
        address addressGlobalPauseOperation,
        address addressInsuranceRegistry
    ) external initializer {
        _stakedAmount = 10 * 1e18;
        _tokenGSZT = IERC20Upgradeable(addressGSZT);
        _insuranceRegistry = IInsuranceRegistry(addressInsuranceRegistry);
        _globalPauseOperation = IGlobalPauseOperation(addressGlobalPauseOperation);
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
        uint256 claimID, 
        uint256 timeInHours
    ) external onlyAdmin {
        claims[claimID].votingInfo[claimID].votingEndTime = timeInHours * 1 hours;
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
        uint8 permitV,
        bytes32 permitR, 
        bytes32 permitS
    ) public override returns(bool) {
        ++_claimID;
        Claim storage newClaim = claims[_claimID];
        newClaim.categoryID = categoryID;
        newClaim.subcategoryID = subcategoryID;
        newClaim.claimID = _claimID;
        newClaim.claimer = _msgSender();
        newClaim.proof = proof;
        newClaim.claimAmountRequested = requestedClaimAmount;
        newClaim.votingInfo[_claimID].votingStartTime = block.timestamp + TIME_BEFORE_VOTING_START;
        newClaim.votingInfo[_claimID].votingEndTime = newClaim.votingInfo[_claimID].votingStartTime + VOTING_END_TIME;
        ++individualClaims[_msgSender()];
        ++productSpecificClaims[categoryID][subcategoryID];
        ++_openClaimsCount;
        _insuranceRegistry.claimAdded(categoryID, subcategoryID);
        bool success = _globalPauseOperation.pauseOperation();
        if(!success) {
            revert Claim__PausedOperationFailedError();
        }
        _tokenPermitDAI.safePermit(_msgSender(), address(this), _stakedAmount, deadline, permitV, permitR, permitS);
        _tokenDAI.safeTransferFrom(_msgSender(), address(this), _stakedAmount);
        emit NewClaimCreated(_msgSender(), _claimID, proof);
        return true;
    }

    function vote(
        uint256 claimID, 
        bool support
    ) external override returns(bool) {
        /// checks are made in order
        /// 1. making sure voting time has started
        /// 2. has the user voted or not
        /// 3. if not, whether the user is voting within the voting time limit
        if (claims[claimID].votingInfo[claimID].votingStartTime > block.timestamp) {
            revert Claim__VotingNotYetStartedError();
        }
        if (claims[claimID].receipts[_msgSender()].hasVoted) {
            revert Claim__UserAlreadyVotedError();
        }
        if (claims[claimID].votingInfo[claimID].votingEndTime < block.timestamp) {
            revert Claim__VotingTimeEndedError();
        }
        claims[claimID].receipts[_msgSender()].support = support;
        claims[claimID].receipts[_msgSender()].votes = _tokenGSZT.balanceOf(_msgSender());
        claims[claimID].receipts[_msgSender()].hasVoted = true;

        if ((isAdvisor[_msgSender()]) && (claims[claimID].votingInfo[claimID].challengedCounts == 2)) {
            if (support) {
                claims[claimID].votingInfo[claimID].advisorForVotes += claims[claimID].receipts[_msgSender()].votes;
            }
            else {
                claims[claimID].votingInfo[claimID].advisorAgainstVotes += claims[claimID].receipts[_msgSender()].votes;
            }
        }
        else {
            if (support) {
                claims[claimID].votingInfo[claimID].forVotes += claims[claimID].receipts[_msgSender()].votes;
            }
            else {
                claims[claimID].votingInfo[claimID].againstVotes += claims[claimID].receipts[_msgSender()].votes;
            }
        }
        return true;
    }

    /// @dev this function aims to finalize the claim decision, based on the claim voting
    /// @param claimID: unique insurance claim _claimID
    function claimDecision(uint256 claimID) external override returns(bool) {
        if (
            (claims[claimID].votingInfo[claimID].votingEndTime + AFTER_VOTING_WAIT_PERIOD) > 
            block.timestamp
        ) {
            revert Claim__VotingDecisionNotYetFinalizedError();
        }
        if (claims[claimID].isChallenged) {
            revert Claim__DecisionChallengedError();
        }
        uint256 totalCommunityVotes = (
            claims[claimID].votingInfo[claimID].forVotes + 
            claims[claimID].votingInfo[claimID].againstVotes
        );
        if (claims[claimID].votingInfo[claimID].challengedCounts == 2) {
            uint256 totalAdvisorVotes = (
                claims[claimID].votingInfo[claimID].advisorForVotes + 
                claims[claimID].votingInfo[claimID].advisorAgainstVotes
            );
            uint256 forAdvisorVotesEligible = (
                (claims[claimID].votingInfo[claimID].advisorForVotes >= 
                claims[claimID].votingInfo[claimID].advisorAgainstVotes) ? 
                ((claims[_claimID].votingInfo[_claimID].forVotes * 100) / totalAdvisorVotes) : 0
            );
            /// even if all the community votes are in favor, but, 49% of the voting power will be 
            /// given to the advisors in the final claim decision round.
            /// Community --> (100 * 0.51) = 51%    Advisors -->  (60 * 0.49) = 29.4%
            /// Total  = 51% + 29.4% < 80% (needed to get approved)
            /// keeping >= 59% instead of 60% because of underflow value in forAdvisorVotesEligible
            if (forAdvisorVotesEligible >= 59) {
                uint256 forVotesEligible = (
                    (claims[claimID].votingInfo[claimID].forVotes > 
                    claims[claimID].votingInfo[claimID].againstVotes) ? 
                    ((claims[claimID].votingInfo[claimID].forVotes * 100) / totalCommunityVotes) : 1
                );
                uint256 supportPercent = (
                    ((forAdvisorVotesEligible * 49) / 100) + 
                    ((forVotesEligible * 51) / 100)
                );
                claims[claimID].accepted = (supportPercent >= 80) ? true : false;
            }
            else {
                claims[claimID].accepted = false;
            }
        }
        else {
            uint256 forVotesEligible = (
                (claims[claimID].votingInfo[claimID].forVotes > 
                claims[claimID].votingInfo[claimID].againstVotes) ? 
                ((claims[claimID].votingInfo[claimID].forVotes * 100) / totalCommunityVotes) : 1
            );
            claims[claimID].accepted = (forVotesEligible >= 80) ? true : false;
        }
        claims[claimID].closed = true;
        if (claims[claimID].accepted) {
            uint256 totalAmountStaked = (
                _stakedAmount * (claims[claimID].votingInfo[claimID].challengedCounts + 1)
            );
            _tokenDAI.safeTransfer(claims[claimID].claimer, totalAmountStaked);
        }
        --_openClaimsCount;
        return true;
    }

    /// @notice this function give access to user to challenge the claim decision
    /// claimID: unique generated insurance claim ID
    /// @param deadline: DAI ERC20 token permit deadline
    /// @param permitV: DAI ERC20 token permit signature (value v)
    /// @param permitR: DAI ERC20 token permit signature (value r)
    /// @param permitS: DAI ERC20 token permit signature (value s)
    function challengeDecision(
        uint256 claimID,
        uint256 deadline, 
        uint8 permitV, 
        bytes32 permitR, 
        bytes32 permitS
    ) external override {
        if ((!claims[claimID].closed) || (!claims[claimID].isChallenged)) {
            revert Claim__DecisionNotYetTakenError();
        }
        if (claims[claimID].votingInfo[claimID].challengedCounts >= 2) {
            revert Claim__DecisionNoLongerCanBeChallengedError();
        }
        claims[claimID].isChallenged = true;
        // global _claimID, as the new registered claim will be a challenged claim
        // and, its voting count needs to be incremented accordingly
        ++claims[_claimID].votingInfo[_claimID + 1].challengedCounts; 
        createClaim(
            claims[claimID].categoryID,
            claims[claimID].subcategoryID,
            claims[claimID].proof,
            claims[claimID].claimAmountRequested,
            deadline, 
            permitV, 
            permitR, 
            permitS
        );
    }

    /// @notice this function aims to let user view their voting info for a particular claim ID
    /// @param claimID: unique insurance claim ID
    function viewVoteReceipt(
        uint256 claimID
    ) external view override returns(bool, bool, uint256) {
        return (
            claims[claimID].receipts[_msgSender()].hasVoted,
            claims[claimID].receipts[_msgSender()].support,
            claims[claimID].receipts[_msgSender()].votes
        );
    }

    /// @notice this function returns the latest claim ID
    function getClaimID() external view override returns(uint256) {
        return _claimID;
    }

    /// @notice this function aims to return the relevant infos' about the particular claim ID
    /// @param claimID: unique insurance claim ID
    function getVotingInfo(
        uint256 claimID
    ) external view override returns(
        uint256, uint256, uint256, uint256, uint256, uint256, uint256
    ) {
        VotingInfo storage claim = claims[claimID].votingInfo[claimID];
        return (
            claim.votingStartTime, 
            claim.votingEndTime, 
            claim.forVotes, 
            claim.againstVotes, 
            claim.advisorForVotes, 
            claim.advisorAgainstVotes, 
            claim.challengedCounts
        );
    }
}