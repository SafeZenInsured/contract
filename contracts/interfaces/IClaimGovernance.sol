// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/// Report any bug or issues at:
/// @custom:security-contact anshik@safezen.finance

interface IClaimGovernance {

    /// Custom Error Codes
    error Claim__VotingTimeEndedError();
    error Claim__UserAlreadyVotedError();
    error Claim__ImmutableChangesError();
    error Claim__DecisionChallengedError();
    error Claim__VotingNotYetStartedError();
    error Claim__DecisionNotYetTakenError();
    error Claim__PausedOperationFailedError();
    error Claim__VotingDecisionNotYetFinalizedError();
    error Claim__DecisionNoLongerCanBeChallengedError();

    event NewClaimCreated(address indexed userAddress, uint256 indexed claimID, string indexed proof);

    function createClaim(
        uint256 categoryID,
        uint256 subCategoryID, 
        string memory proof, 
        uint256 requestedClaimAmount,
        uint256 deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external returns(bool); 

    function vote(
        uint256 claimID, 
        bool support
    ) external returns(bool);

    function claimDecision(
        uint256 claimID
    ) external returns(bool);

    function challengeDecision(
        uint256 claimID,
        uint256 deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external;

    function viewVoteReceipt(
        uint256 claimID
    ) external view returns(bool, bool, uint256);

    function getClaimID() external view returns(uint256);

    function getVotingInfo(
        uint256 claimID
    ) external view returns(
        uint256, uint256, uint256, uint256, uint256, uint256, uint256
    );
}   