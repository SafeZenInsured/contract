// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/// @title Stablecoin Zero Premium Insurance Controller Contract
/// @author Anshik Bansal <anshik@safezen.finance>

import "@openzeppelin/contracts/access/Ownable.sol";
import "./../../../interfaces/IStablecoinZPController.sol";

contract StablecoinZPController is Ownable, IStablecoinZPController {
    uint256 public override stablecoinID;
    uint256 public override latestVersion; // version changes whenever there is asset liquidation, i.e. insurance gets activated
    
    struct VersionInfo {
        uint256 liquidation;
        uint256 riskPoolCategory; // liquidation based on risk-pool category
    }

    struct StablecoinInfo {
        string stablecoinName;
        address deployedAddress;
        uint256 startVersionBlock;
        uint256 lastUpdatedVersionBlock;
    }

    struct StablecoinRiskInfo {
        bool isUpdated;
        bool isCommunityGoverned;
        uint256 riskFactor;
        uint256 riskPoolCategory; // low = 1, medium = 2, or high = 3, notCovered = 4
    }

    mapping (uint256 => StablecoinInfo) public stablecoinsInfo;

    // stablecoinID => VersionNumber => StablecoinInfo
    mapping(uint256 => mapping(uint256 => StablecoinRiskInfo)) public stablecoinsRiskInfo;

    mapping(uint256 => VersionInfo) public versionLiquidationFactor; // for each insurance coverage event, keeping a track of liquidation percent

    event NewStablecoinAdded(uint256 indexed stablecoinID_, string indexed stablecoinName);

    constructor() {
        VersionInfo storage versionInfo = versionLiquidationFactor[0];
        versionInfo.liquidation = 100;
    }

    function updateRiskFactor(uint256 stablecoinID_, uint256 riskFactor) external onlyOwner {
        StablecoinRiskInfo storage stablecoinRiskInfo = stablecoinsRiskInfo[stablecoinID_][latestVersion];
        stablecoinRiskInfo.riskFactor = riskFactor;
    }

    function liquidateRiskPool(uint256 riskPoolCategory, uint256 liquidationFactor) external onlyOwner {
        versionLiquidationFactor[latestVersion].liquidation = liquidationFactor;
        versionLiquidationFactor[latestVersion].riskPoolCategory = riskPoolCategory;
        _addNewVersion();
    }

    /// first adding a new version to ensure that risk category is applied from the time this function gets called
    function updateRiskPoolCategory(uint256 stablecoinID_, uint256 riskPoolCategory) external onlyOwner {
        uint latestVersion_ = latestVersion + 1;
        StablecoinRiskInfo storage stablecoinRiskInfo = stablecoinsRiskInfo[stablecoinID_][latestVersion_];
        stablecoinRiskInfo.isUpdated = true;
        stablecoinRiskInfo.riskPoolCategory = riskPoolCategory;
        stablecoinsInfo[stablecoinID_].lastUpdatedVersionBlock = latestVersion_;
        _addNewVersion();
    }

    function addCoveredStablecoin(
        string memory stablecoinName,
        address deployedAddress,
        bool isCommunityGoverned,
        uint256 riskFactor,
        uint256 riskPoolCategory
    ) external onlyOwner {
        StablecoinInfo storage stablecoinInfo = stablecoinsInfo[stablecoinID];
        stablecoinInfo.stablecoinName = stablecoinName;
        stablecoinInfo.deployedAddress = deployedAddress;
        stablecoinInfo.startVersionBlock = latestVersion + 1;
        stablecoinInfo.lastUpdatedVersionBlock = latestVersion + 1;
        StablecoinRiskInfo storage stablecoinRiskInfo = stablecoinsRiskInfo[stablecoinID][latestVersion + 1];
        stablecoinRiskInfo.isUpdated = true;
        stablecoinRiskInfo.isCommunityGoverned = isCommunityGoverned;
        stablecoinRiskInfo.riskFactor = riskFactor;
        stablecoinRiskInfo.riskPoolCategory = riskPoolCategory;
        ++stablecoinID;
        _addNewVersion();
        emit NewStablecoinAdded(stablecoinID, stablecoinName);
    }

    function _addNewVersion() internal {
        latestVersion += 1;
        versionLiquidationFactor[latestVersion].liquidation = 100;
    }

    function getStablecoinInfo(
        uint256 stablecoinID_
    ) external view returns(string memory stablecoinName, address stablecoinAddress) {
        StablecoinInfo storage stablecoinInfo = stablecoinsInfo[stablecoinID_];
        return (stablecoinInfo.stablecoinName, stablecoinInfo.deployedAddress);
    }

    function getStablecoinRiskCategory(uint256 stablecoinID_, uint256 version) external view returns (uint256) {
        return stablecoinsRiskInfo[stablecoinID_][version].riskPoolCategory;
    }

    function ifStablecoinUpdated(uint256 stablecoinID_, uint256 version) external view returns (bool) {
        return stablecoinsRiskInfo[stablecoinID_][version].isUpdated;
    }

    function getProtocolStartVersionInfo(uint256 stablecoinID_) external view returns(uint256) {
        return stablecoinsInfo[stablecoinID_].startVersionBlock;
    }

    function isRiskPoolLiquidated(uint256 version, uint256 riskPoolCategory) external view returns (bool) {
        bool isTrue = (versionLiquidationFactor[version].riskPoolCategory == riskPoolCategory);
        return isTrue;
    }

    function getLiquidationFactor(uint256 version) external view returns(uint256) {
        return versionLiquidationFactor[version].liquidation;
    }
}