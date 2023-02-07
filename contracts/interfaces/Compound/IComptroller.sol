// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./ICErc20.sol";

interface IComptroller {

    function claimVenus(address userAddress, ICErc20[] memory vTokens) external;

    function venusAccrued(address userAddress) external view returns(uint256);

    function getAllMarkets() external view returns (ICErc20[] memory);

}