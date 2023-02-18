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
/// [PRODUCTION TODO] uint256 public constant VOTING_END_TIME = 48 hours;
/// [PRODUCTION TODO] uint256 public constant TIME_BEFORE_VOTING_START = 12 hours;
/// [PRODUCTION TODO] uint256 public constant AFTER_VOTING_WAIT_PERIOD = 12 hours;
contract ClaimGovernance is IClaimGovernance, BaseUpgradeablePausable {

    // :::::::::::::: STATE VARIABLES AND DECLARATIONS :::::::::::::::: //

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeERC20Upgradeable for IERC20PermitUpgradeable;

    /// claimID: unique insurance claim ID
    /// stakedAmount: stake amount to register the claim
    /// openClaimsCount: count of the open insurance claims
    /// VOTING_END_TIME: voting maximum duration in hours
    /// TIME_BEFORE_VOTING_START: time before voting starts, so as users can be notified
    /// AFTER_VOTING_WAIT_PERIOD: voting challenge duration
    uint256 public tokenID;
    uint256 public claimID;
    uint256 public stakedAmount;
    uint256 public openClaimsCount;
    uint256 public constant VOTING_END_TIME = 5 minutes;
    uint256 public constant TIME_BEFORE_VOTING_START = 1 minutes;
    uint256 public constant AFTER_VOTING_WAIT_PERIOD = 1 minutes;

    /// tokenGSZT: SafeZen Governance contract interface
    /// insuranceRegistry: Insurance Registry contract interface
    /// globalPauseOperation: Global Pause Operation contract interface
    IERC20Upgradeable public tokenGSZT;
    IInsuranceRegistry public insuranceRegistry;
    IGlobalPauseOperation public globalPauseOperation;

    /// @dev collects essential insurance claim info
    /// claimer: claimer wallet address
    /// claimID: unique insurance claim ID
    /// categoryID: insurance category, e.g., stablecoin depeg insurance.
    /// subcategoryID: insurance sub-category, e.g., USDC depeg coverage, DAI depeg coverage.
    /// claimAmountRequested: claim amount requested by claimer.
    /// proof: digital uploaded proof of the claiming event 
    /// closed: checks if the insurance claim is closed or not.
    /// accepted: checks if the insurance claim request has been accpeted or not.
    /// isChallenged: checks if the insurance claim has been challenged or not.
    /// votingInfo: maps:: claimID(uint256) => VotingInfo(struct)
    /// receipts: maps:: addressClaimant(address) => Receipt(struct)
    struct Claim {
        address claimer;
        uint256 claimID;
        uint256 categoryID; 
        uint256 subcategoryID;
        uint256 claimAmountRequested;
        string proof;
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
        bool support;
        bool hasVoted;
        uint256 votes;
    }

    /// Maps :: claimID(uint256) => Claim(struct)
    mapping(uint256 => Claim) public claims;

    /// Maps :: addressUser(address) => isAdvisor(bool)
    mapping(address => bool) public isAdvisor;

    /// Maps :: addressUser(uint256) => individualClaims(uint256)
    /// @notice stores user claim history, i.e.,
    /// if a user have filed most claims, then user investments are generally risky.
    mapping(address => uint256) public individualClaims;

    /// @notice Maps :: tokenID(uint256) => tokenAddress(address)
    mapping(uint256 => address) public permissionedTokens;

    /// Maps :: categoryID(uint256) => subCategoryID(uint256) => productSpecificClaims
    /// @notice mapping the insurance product specific claims count to date.
    /// the higher the number, more the risky the platform will be.
    mapping(uint256 => mapping(uint256 => uint256)) public productSpecificClaims;

    /// @notice initialize function, called during the contract initialization
    /// @param addressDAI: DAI ERC20 token address
    /// @param addressGSZT: GSZT ERC20 token address
    /// @param addressInsuranceRegistry: Insurance Registry contract address
    /// @param addressGlobalPauseOperation: Global Pause Operation contract address
    function initialize(
        address addressDAI,
        address addressGSZT,
        address addressInsuranceRegistry,
        address addressGlobalPauseOperation
    ) external initializer {
        stakedAmount = 1e19;
        permissionedTokens[tokenID] = addressDAI;
        tokenGSZT = IERC20Upgradeable(addressGSZT);
        insuranceRegistry = IInsuranceRegistry(addressInsuranceRegistry);
        globalPauseOperation = IGlobalPauseOperation(addressGlobalPauseOperation);
        __BaseUpgradeablePausable_init(_msgSender());
        emit InitializedContractClaimGovernance(_msgSender());
    }

    /// @notice this function aims to change voting end time in case if certain claim /
    /// / require additional time. for e.g., awaiting additional inputs to reserve their decisions.
    /// @param claimID_: unique insurance claim ID
    /// @param timeInHours: new time interval for voting period
    function updateVotingEndTime(
        uint256 claimID_, 
        uint256 timeInHours
    ) external onlyAdmin {
        claims[claimID_].votingInfo[claimID_].votingEndTime = block.timestamp + (timeInHours * 1 hours);
        emit UpdatedVotingEndTime(claimID_, timeInHours);
    }

    /// @notice this function assigns advisor role to the provided user wallet address
    /// @param addressUser: user wallet address
    function addNewAdvisor(address addressUser) external onlyAdmin {
        isAdvisor[addressUser] = true;
        emit AddedNewAdvisor(addressUser);
    }

    /// @notice this function updates the stake amount, needed to create a claim.
    /// @param updatedStakeAmount: updated stake amount, required for registering a claim
    function updateStakeAmount(uint256 updatedStakeAmount) external onlyAdmin {
        stakedAmount = updatedStakeAmount;
        emit UpdatedStakeAmount(updatedStakeAmount);
    }

    /// @notice this function facilitates adding new supported payment tokens for GENZ ERC20 token purchase
    /// @param tokenAddress: ERC20 token address
    function addTokenAddress(address tokenAddress) external onlyAdmin {
        ++tokenID;
        permissionedTokens[tokenID] = tokenAddress;
        emit NewTokenAdded(tokenID, tokenAddress);
    }

    /// @dev this function aims to pause the contracts' certain functions temporarily
    function pause() external onlyAdmin {
        _pause();
    }

    /// @dev this function aims to resume the complete contract functionality
    function unpause() external onlyAdmin {
        _unpause();
    }

    /// @notice this function facilitates claimant to create an insurance claim
    /// @param categoryID: insurance category, e.g., stablecoin depeg insurance.
    /// @param subcategoryID: insurance sub-category, e.g., USDC depeg coverage, DAI depeg coverage.
    /// @param proof: insurance claim proof, e.g. onchain transaction records, soft documents etc.
    /// @param requestedClaimAmount: requested insurance claim amount
    /// @param deadline: ERC20 token permit deadline
    /// @param permitV: ERC20 token permit signature (value v)
    /// @param permitR: ERC20 token permit signature (value r)
    /// @param permitS: ERC20 token permit signature (value s)
    function createClaim(
        uint256 tokenID_,
        uint256 categoryID,
        uint256 subcategoryID, 
        string memory proof, 
        uint256 requestedClaimAmount,
        uint256 deadline, 
        uint8 permitV,
        bytes32 permitR, 
        bytes32 permitS
    ) external override returns(bool) {
        bool success = _createClaim(_msgSender(), tokenID_, categoryID, subcategoryID, proof, requestedClaimAmount, deadline, permitV, permitR, permitS);
        if(!success) {
            revert ClaimGovernance__UnsuccessfulClaimRegistrationError();
        }
        return true;
    }

    /// @notice this function facilitates users to cast their votes for the received claims
    /// @param claimID_: unique insurance claim ID
    /// @param support: users voting decision whether to support or not support the particular claim
    function vote(
        uint256 claimID_, 
        bool support
    ) external override returns(bool) {
        /// checks are made in order
        /// 1. making sure voting time has started
        /// 2. has the user voted or not
        /// 3. if not, whether the user is voting within the voting time limit
        Receipt storage userVoteReceipt = claims[claimID_].receipts[_msgSender()];
        VotingInfo storage userVotingInfo = claims[claimID_].votingInfo[claimID_];
        if (userVotingInfo.votingStartTime > block.timestamp) {
            revert ClaimGovernance__VotingNotYetStartedError();
        }
        if (userVoteReceipt.hasVoted) {
            revert ClaimGovernance__UserAlreadyVotedError();
        }
        if (userVotingInfo.votingEndTime < block.timestamp) {
            revert ClaimGovernance__VotingTimeEndedError();
        }
        
        userVoteReceipt.hasVoted = true;
        userVoteReceipt.support = support;
        userVoteReceipt.votes = tokenGSZT.balanceOf(_msgSender());

        if ((userVotingInfo.challengedCounts == 2) && (isAdvisor[_msgSender()])) {
            if (support) {
                userVotingInfo.advisorForVotes += userVoteReceipt.votes;
            }
            else {
                userVotingInfo.advisorAgainstVotes += userVoteReceipt.votes;
            }
        }
        else {
            if (support) {
                userVotingInfo.forVotes += userVoteReceipt.votes;
            }
            else {
                userVotingInfo.againstVotes += userVoteReceipt.votes;
            }
        }
        emit UserVoted(claimID_, _msgSender(), support, userVoteReceipt.votes);
        return true;
    }

    /// @dev this function aims to finalize the claim decision, based on the claim voting
    /// @param tokenID_: unique token ID for acceptable token address
    /// @param claimID_: unique insurance claim ID
    function claimDecision(
        uint256 tokenID_, 
        uint256 claimID_
    ) external override returns(bool) {
        address tokenAddress = permissionedTokens[tokenID_];
        if(tokenAddress == address(0)) {
            revert ClaimGovernance__ZeroAddressError();
        }
        VotingInfo memory userVotingInfo = claims[claimID_].votingInfo[claimID_];
        if (
            (userVotingInfo.votingEndTime + AFTER_VOTING_WAIT_PERIOD) > 
            block.timestamp
        ) {
            revert ClaimGovernance__VotingDecisionNotYetFinalizedError();
        }
        if (claims[claimID_].isChallenged) {
            revert ClaimGovernance__DecisionChallengedError();
        }
        uint256 totalCommunityVotes = (userVotingInfo.forVotes + userVotingInfo.againstVotes);
        if (userVotingInfo.challengedCounts == 2) {
            uint256 totalAdvisorVotes = (
                userVotingInfo.advisorForVotes + userVotingInfo.advisorAgainstVotes
            );
            uint256 forAdvisorVotesEligible = (
                (userVotingInfo.advisorForVotes >= userVotingInfo.advisorAgainstVotes) ? 
                ((userVotingInfo.forVotes * 100) / totalAdvisorVotes) : 0
            );
            /// even if all the community votes are in favor, but, 49% of the voting power will be 
            /// given to the advisors in the final claim decision round.
            /// Community --> (100 * 0.51) = 51%    Advisors -->  (60 * 0.49) = 29.4%
            /// Total  = 51% + 29.4% < 80% (needed to get approved)
            /// keeping >= 59% instead of 60% because of underflow value in forAdvisorVotesEligible
            if (forAdvisorVotesEligible >= 59) {
                uint256 forVotesEligible = (
                    (userVotingInfo.forVotes > userVotingInfo.againstVotes) ? 
                    ((userVotingInfo.forVotes * 100) / totalCommunityVotes) : 1
                );
                uint256 supportPercent = (
                    ((forAdvisorVotesEligible * 49) / 100) + 
                    ((forVotesEligible * 51) / 100)
                );
                claims[claimID_].accepted = (supportPercent >= 80) ? true : false;
            }
            else {
                claims[claimID_].accepted = false;
            }
        }
        else {
            uint256 forVotesEligible = (
                (userVotingInfo.forVotes > userVotingInfo.againstVotes) ? 
                ((userVotingInfo.forVotes * 100) / totalCommunityVotes) : 1
            );
            claims[claimID_].accepted = (forVotesEligible >= 80) ? true : false;
        }
        claims[claimID_].closed = true;
        if (claims[claimID_].accepted) {
            uint256 totalAmountStaked = (
                stakedAmount * (claims[claimID_].votingInfo[claimID_].challengedCounts + 1)
            );
            IERC20Upgradeable(tokenAddress).safeTransfer(claims[claimID_].claimer, totalAmountStaked);
        }
        --openClaimsCount;
        emit ClaimDecisionResult(claimID_, claims[claimID_].accepted);
        return true;
    }

    /// @notice this function give access to user to challenge the claim decision
    /// @param tokenID_: unique token ID for acceptable token address
    /// @param claimID_: unique generated insurance claim ID
    /// @param deadline: DAI ERC20 token permit deadline
    /// @param permitV: DAI ERC20 token permit signature (value v)
    /// @param permitR: DAI ERC20 token permit signature (value r)
    /// @param permitS: DAI ERC20 token permit signature (value s)
    function challengeDecision(
        uint256 tokenID_,
        uint256 claimID_,
        uint256 deadline, 
        uint8 permitV, 
        bytes32 permitR, 
        bytes32 permitS
    ) external override returns(bool) {
        if ((!claims[claimID_].closed) || (!claims[claimID_].isChallenged)) {
            revert ClaimGovernance__VotingDecisionNotYetFinalizedError();
        }
        if (claims[claimID_].votingInfo[claimID_].challengedCounts >= 2) {
            revert ClaimGovernance__DecisionNoLongerCanBeChallengedError();
        }
        claims[claimID_].isChallenged = true;
        // global claimID, as the new registered claim will be a challenged claim
        // and, its voting count needs to be incremented accordingly
        ++claims[claimID].votingInfo[claimID + 1].challengedCounts; 
        bool success = _createClaim(
            _msgSender(),
            tokenID_,
            claims[claimID_].categoryID,
            claims[claimID_].subcategoryID,
            claims[claimID_].proof,
            claims[claimID_].claimAmountRequested,
            deadline, 
            permitV, 
            permitR, 
            permitS
        );
        if(!success) {
            revert ClaimGovernance__UnsuccessfulClaimRegistrationError();
        }
        emit ClaimChallenged(_msgSender(), claimID_);
        return true;
    }

    /// @notice this function facilitates claimant to create an insurance claim
    /// @param categoryID: insurance category, e.g., stablecoin depeg insurance.
    /// @param subcategoryID: insurance sub-category, e.g., USDC depeg coverage, DAI depeg coverage.
    /// @param proof: insurance claim proof, e.g. onchain transaction records, soft documents etc.
    /// @param requestedClaimAmount: requested insurance claim amount
    /// @param deadline: ERC20 token permit deadline
    /// @param permitV: ERC20 token permit signature (value v)
    /// @param permitR: ERC20 token permit signature (value r)
    /// @param permitS: ERC20 token permit signature (value s)
    function _createClaim(
        address addressUser,
        uint256 tokenID_,
        uint256 categoryID,
        uint256 subcategoryID, 
        string memory proof, 
        uint256 requestedClaimAmount,
        uint256 deadline, 
        uint8 permitV,
        bytes32 permitR, 
        bytes32 permitS
    ) private returns(bool) {
        address tokenAddress = permissionedTokens[tokenID_];
        if(tokenAddress == address(0)) {
            revert ClaimGovernance__ZeroAddressError();
        }
        IERC20Upgradeable token = IERC20Upgradeable(tokenAddress);
        IERC20PermitUpgradeable tokenWithPermit = IERC20PermitUpgradeable(tokenAddress);
        if (stakedAmount > token.balanceOf(addressUser)) {
            revert CoverageGovernance__InsufficientBalanceError();
        }
        ++claimID;
        Claim storage newClaim = claims[claimID];
        newClaim.categoryID = categoryID;
        newClaim.subcategoryID = subcategoryID;
        newClaim.claimID = claimID;
        newClaim.claimer = addressUser;
        newClaim.proof = proof;
        newClaim.claimAmountRequested = requestedClaimAmount;
        newClaim.votingInfo[claimID].votingStartTime = block.timestamp + TIME_BEFORE_VOTING_START;
        newClaim.votingInfo[claimID].votingEndTime = newClaim.votingInfo[claimID].votingStartTime + VOTING_END_TIME;
        ++openClaimsCount;
        ++individualClaims[addressUser];
        ++productSpecificClaims[categoryID][subcategoryID];
        insuranceRegistry.claimAdded(categoryID, subcategoryID);
        bool success = globalPauseOperation.pauseOperation();
        if(!success) {
            revert ClaimGovernance__PausedOperationFailedError();
        }
        tokenWithPermit.safePermit(addressUser, address(this), stakedAmount, deadline, permitV, permitR, permitS);
        token.safeTransferFrom(addressUser, address(this), stakedAmount);
        emit NewClaimCreated(addressUser, claimID, proof);
        return true;
    }
}