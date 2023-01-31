// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.16;

interface IAAVEImplementation {

    /// SafeZen Implementation

    function supplyToken(
        address tokenAddress, 
        address rewardTokenAddress, 
        uint256 amount
    ) external returns(bool);

    function withdrawToken(
        address tokenAddress, 
        address rewardTokenAddress, 
        uint256 _amount
    ) external returns(bool);

    function calculateUserBalance(address rewardTokenAddress) external view returns(uint256);

}