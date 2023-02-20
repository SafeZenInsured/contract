// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/// Report any bug or issues at:
/// @custom:security-contact anshik@safezen.finance

interface IClaimGovernance {

    error ClaimGovernance__ZeroAddressError();

    error ClaimGovernance__VotingTimeEndedError();

    error ClaimGovernance__UserAlreadyVotedError();

    error ClaimGovernance__ClaimUnregisteredError();

    error ClaimGovernance__DecisionChallengedError();

    error ClaimGovernance__VotingNotYetStartedError();

    error ClaimGovernance__PausedOperationFailedError();

    error CoverageGovernance__InsufficientBalanceError();

    error ClaimGovernance__VotingDecisionNotYetFinalizedError();

    error ClaimGovernance__UnsuccessfulClaimRegistrationError();

    error ClaimGovernance__DecisionNoLongerCanBeChallengedError();


    /// @notice emits after the contract has been initialized
    event InitializedContractClaimGovernance(address indexed addressUser);

    event UpdatedVotingEndTime(uint256 indexed claimID, uint256 indexed timeInHours);

    event AddedNewAdvisor(address indexed addressUser);

    event UpdatedStakeAmount(uint256 indexed updatedStakeAmount);

    event NewClaimCreated(
        address indexed addressClaimant, 
        uint256 indexed claimID, 
        string indexed proof
    );

    /// @notice emits when the new token is added for GENZ ERC20 token purchase
    event NewTokenAdded(uint256 indexed tokenID, address indexed tokenAddress);

    event UserVoted(
        uint256 indexed claimID,
        address indexed addressUser,
        bool indexed support,
        uint256 votes
    );

    event ClaimDecisionResult(
        uint256 claimID,
        bool isAccepted
    );

    event ClaimChallenged(
        address indexed addressClaimant, 
        uint256 indexed claimID
    );

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
    ) external returns(bool);

    function vote(
        uint256 claimID_, 
        bool support
    ) external returns(bool);

    function claimDecision(
        uint256 tokenID_, 
        uint256 claimID_
    ) external returns(bool);

    function challengeDecision(
        uint256 tokenID_,
        uint256 claimID_,
        uint256 deadline, 
        uint8 permitV, 
        bytes32 permitR, 
        bytes32 permitS
    ) external returns(bool);
}   