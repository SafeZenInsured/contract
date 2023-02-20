// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

interface ISmartContractZPController {

    event NewProtocolAdded(uint256 indexed protocolID_, string indexed protocolName);

    function protocolID() external view returns(uint256);

    function latestVersion() external view returns(uint256);

    function getProtocolInfo(
        uint256 protocolID_
    ) external view returns(string memory protocolName, address protocolAddress);

    function ifProtocolUpdated(uint256 protocolID_, uint256 version) external view returns (bool);

    function getProtocolRiskCategory(uint256 protocolID_) external view returns(uint256);

    function getProtocolRiskCategory(uint256 protocolID_, uint256 version) external view returns (uint256);

    function isRiskPoolLiquidated(uint256 version, uint256 riskPoolCategory) external view returns (bool);

    function getLiquidationFactor(uint256 version) external view returns(uint256);
}