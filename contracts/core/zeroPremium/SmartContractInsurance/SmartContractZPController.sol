// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/// @title Smart Contract Zero Premium Insurance Controller Contract
/// @author Anshik Bansal <anshik@safezen.finance>

/// Importing required interfaces
import "./../../../interfaces/ISmartContractZPController.sol";

/// Importing required contracts
import "./../../../BaseUpgradeablePausable.sol";

contract SmartContractZPController is ISmartContractZPController, BaseUpgradeablePausable {
    uint256 public override protocolID;
    uint256 public override latestVersion; // version changes whenever there is asset liquidation, i.e. insurance gets activated
    uint256 private withdrawalFee;

    struct VersionInfo {
        uint256 liquidation;
        uint256 riskPoolCategory; // liquidation based on risk-pool category
    }

    struct ProtocolInfo {
        string protocolName;
        address deployedAddress;
        uint256 startVersionBlock;
        uint256 lastUpdatedVersionBlock;
    }

    struct ProtocolRiskInfo {
        bool isUpdated;
        bool isCommunityGoverned;
        uint256 riskFactor;
        uint256 riskPoolCategory; // low = 1, medium = 2, or high = 3, notCovered = 4
    }

    mapping (uint256 => ProtocolInfo) public protocolsInfo;

    // protocolID => VersionNumber => ProtocolInfo
    mapping(uint256 => mapping(uint256 => ProtocolRiskInfo)) public protocolsRiskInfo;

    mapping(uint256 => VersionInfo) public versionLiquidationFactor; // for each insurance coverage event, keeping a track of liquidation percent

    function initialize() external initializer {
        VersionInfo storage versionInfo = versionLiquidationFactor[0];
        versionInfo.liquidation = 100;
    }

    function updateRiskFactor(uint256 protocolID_, uint256 riskFactor) external onlyAdmin {
        ProtocolRiskInfo storage protocolRiskInfo = protocolsRiskInfo[protocolID_][latestVersion];
        protocolRiskInfo.riskFactor = riskFactor;
    }

    function liquidateRiskPool(uint256 riskPoolCategory, uint256 liquidationFactor) external onlyAdmin {
        versionLiquidationFactor[latestVersion].liquidation = liquidationFactor;
        versionLiquidationFactor[latestVersion].riskPoolCategory = riskPoolCategory;
        _addNewVersion();
    }

    /// first adding a new version to ensure that risk category is applied from the time this function gets called
    function updateRiskPoolCategory(uint256 protocolID_, uint256 riskPoolCategory) external onlyAdmin {
        uint latestVersion_ = latestVersion + 1;
        ProtocolRiskInfo storage protocolRiskInfo = protocolsRiskInfo[protocolID_][latestVersion_];
        protocolRiskInfo.isUpdated = true;
        protocolRiskInfo.riskPoolCategory = riskPoolCategory;
        protocolsInfo[protocolID_].lastUpdatedVersionBlock = latestVersion_;
        _addNewVersion();
    }

    function addCoveredProtocol(
        string memory protocolName,
        address deployedAddress,
        bool isCommunityGoverned,
        uint256 riskFactor,
        uint256 riskPoolCategory
    ) external onlyAdmin {
        ++protocolID;
        ProtocolInfo storage protocolInfo = protocolsInfo[protocolID];
        protocolInfo.protocolName = protocolName;
        protocolInfo.deployedAddress = deployedAddress;
        protocolInfo.startVersionBlock = latestVersion + 1;
        protocolInfo.lastUpdatedVersionBlock = latestVersion + 1;
        ProtocolRiskInfo storage protocolRiskInfo = protocolsRiskInfo[protocolID][latestVersion + 1];
        protocolRiskInfo.isUpdated = true;
        protocolRiskInfo.isCommunityGoverned = isCommunityGoverned;
        protocolRiskInfo.riskFactor = riskFactor;
        protocolRiskInfo.riskPoolCategory = riskPoolCategory;
        _addNewVersion();
        emit NewProtocolAdded(protocolID, protocolName);
    }

    function _addNewVersion() internal {
        ++latestVersion;
        versionLiquidationFactor[latestVersion].liquidation = 100;
    }

    function getProtocolInfo(
        uint256 protocolID_
    ) external view returns(string memory protocolName, address protocolAddress) {
        ProtocolInfo storage protocolInfo = protocolsInfo[protocolID_];
        return (protocolInfo.protocolName, protocolInfo.deployedAddress);
    }

    function getProtocolRiskCategory(uint256 protocolID_, uint256 version) external view returns (uint256) {
        return protocolsRiskInfo[protocolID_][version].riskPoolCategory;
    }

    function ifProtocolUpdated(uint256 protocolID_, uint256 version) external view returns (bool) {
        return protocolsRiskInfo[protocolID_][version].isUpdated;
    }

    function getProtocolStartVersionInfo(uint256 protocolID_) external view returns(uint256) {
        return protocolsInfo[protocolID_].startVersionBlock;
    }

    function isRiskPoolLiquidated(uint256 version, uint256 riskPoolCategory) external view returns (bool) {
        bool isTrue = (versionLiquidationFactor[version].riskPoolCategory == riskPoolCategory);
        return isTrue;
    }

    function getLiquidationFactor(uint256 version) external view returns(uint256) {
        return versionLiquidationFactor[version].liquidation;
    }
}