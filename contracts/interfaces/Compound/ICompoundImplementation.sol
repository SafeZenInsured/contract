// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface ICompoundImplementation {

    /// Custom Error Codes
    error Compound_ZP__LowAmountError();
    error Compound_ZP__LowSupplyAmountError();
    error Compound_ZP__WrongInfoEnteredError();
    error Compound_ZP__ImmutableChangesError();
    error Compound_ZP__TransactionFailedError();
    
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

    function withdrawToken(address tokenAddress, address rewardTokenAddress, uint256 amount) external returns(bool);

    function calculateUserBalance(address rewardTokenAddress) external view returns(uint256, uint256);

}