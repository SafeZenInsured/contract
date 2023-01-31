// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.16;

interface IAAVEImplementation {

    /// Custom Error Codes
    error AAVE_ZP__LowSupplyAmountError(uint256 errorLineNumber);
    error AAVE_ZP__WrongInfoEnteredError(uint256 errorLineNumber);
    error AAVE_ZP__ImmutableChangesError(uint256 errorLineNumber);
    error AAVE_ZP__TransactionFailedError(uint256 errorLineNumber);
    error AAVE_ZP__LowAmountError(uint256 errorLineNumber);

    event SuppliedToken(
        address indexed userAddress, 
        address indexed tokenAddress,
        uint256 indexed amount
    );

    event WithdrawnToken(
        address indexed userAddress, 
        address indexed tokenAddress,
        uint256 indexed amount
    );

    function supplyToken(
        address tokenAddress, 
        address rewardTokenAddress, 
        uint256 amount,
        uint256 deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external returns(bool);

    function withdrawToken(
        address tokenAddress, 
        address rewardTokenAddress, 
        uint256 _amount
    ) external returns(bool);

    function calculateUserBalance(address rewardTokenAddress) external view returns(uint256);

}