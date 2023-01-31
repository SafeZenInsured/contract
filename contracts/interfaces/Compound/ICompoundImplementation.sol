// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface ICompoundImplementation {

    /// Custom Error Codes
    error Compound_ZP__LowSupplyAmountError();
    error Compound_ZP__WrongInfoEnteredError();
    error Compound_ZP__TransactionFailedError();
    
    function supplyToken(address tokenAddress, address rewardTokenAddress, uint256 _amount) external returns(uint256);

    function withdrawToken(address tokenAddress, address rewardTokenAddress, uint256 _amount) external returns(uint256);

    function calculateUserBalance(address rewardTokenAddress) external view returns(uint256);

}