// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.16;

interface IAAVEV3Incentives {

    function claimAllRewardsToSelf(address[] calldata assets)
    external
    returns (address[] memory rewardsList, uint256[] memory claimedAmounts);

    function getRewardsList() external returns(address[] memory);
}