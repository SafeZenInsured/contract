// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import {IPoolAddressesProvider} from './IPoolAddressesProvider.sol';

interface IUiIncentiveDataProviderV3 {
  
  struct UserReserveIncentiveData {
    address underlyingAsset;
    UserIncentiveData aTokenIncentivesUserData;
    UserIncentiveData vTokenIncentivesUserData;
    UserIncentiveData sTokenIncentivesUserData;
  }

  struct UserIncentiveData {
    address tokenAddress;
    address incentiveControllerAddress;
    UserRewardInfo[] userRewardsInformation;
  }

  struct UserRewardInfo {
    string rewardTokenSymbol;
    address rewardOracleAddress;
    address rewardTokenAddress;
    uint256 userUnclaimedRewards;
    uint256 tokenIncentivesUserIndex;
    int256 rewardPriceFeed;
    uint8 priceFeedDecimals;
    uint8 rewardTokenDecimals;
  }

  function getUserReservesIncentivesData(IPoolAddressesProvider provider, address user)
    external
    view
    returns (UserReserveIncentiveData[] memory);
}