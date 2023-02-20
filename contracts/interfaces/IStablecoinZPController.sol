// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

interface IStablecoinZPController {

    function stablecoinID() external view returns(uint256);

    function latestVersion() external view returns(uint256);

    function getStablecoinInfo(
        uint256 stablecoinID_
    ) external view returns(string memory stablecoinName, address stablecoinAddress);

    function ifStablecoinUpdated(uint256 stablecoinID_, uint256 version) external view returns (bool);

    function getStablecoinRiskCategory(uint256 stablecoinID_, uint256 version) external view returns (uint256);

    function isRiskPoolLiquidated(uint256 version, uint256 riskPoolCategory) external view returns (bool);

    function getLiquidationFactor(uint256 version) external view returns(uint256);
}