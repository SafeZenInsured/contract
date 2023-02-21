// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/// @title Insurance Registry Contract
/// @author Anshik Bansal <anshik@safezen.finance>

/// Importing required interfaces
import "./../../interfaces/IBuySellSZT.sol";
import "./../../interfaces/ICoveragePool.sol";
import "./../../interfaces/IClaimGovernance.sol";
import "./../../interfaces/IInsuranceRegistry.sol";
import "@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol";

/// Importing required libraries
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

/// Importing required contracts
import "./../../BaseUpgradeablePausable.sol";

/// Report any bug or issues at:
/// @custom:security-contact anshik@safezen.finance
/// [PRODUCTION TODO: Start CategoryID from 1, and not 0]
contract InsuranceRegistry is IInsuranceRegistry, BaseUpgradeablePausable {

    // :::::::::::::: STATE VARIABLES AND DECLARATIONS :::::::::::::::: //

    /// initVersion: counter to initialize the init one-time function, max value can be 1.
    /// categoryID: insurance category, e.g., stablecoin depeg insurance.
    /// addressCFA: address of the Constant Flow Agreement contract interface
    uint256 public initVersion;
    uint256 public override categoryID;
    uint256 public constant PLATFORM_COST = 90;
    address public addressCFA;

    /// tokenDAI: DAI ERC20 token interface
    /// tokenSZT: SZT ERC20 token interface
    /// buySellSZT:Buy Sell SZT contract interface
    /// coveragePool: Coverage Pool contract interface
    IERC20Upgradeable public tokenDAI;
    IERC20Upgradeable public tokenSZT;
    IBuySellSZT public buySellSZT;
    ICoveragePool public coveragePool;
    IClaimGovernance public claimGovernance;

    /// @notice collects info about the insurance subcategories, e.g., USDC depeg coverage, DAI depeg coverage.
    /// isActive: checks whether insurance given subcategory is active or not.
    /// subCategoryName: insurance subcategory title
    /// info: insurance subcategory info, e.g., algorithmic stablecoin, etc.
    /// logo: insurance subcategory logo, if available
    /// liquidity: insurance maximum coverage amount that can be offered
    /// subCategoryID: subcategory ID
    /// streamFlowRate: insurance premium rate per second
    /// coverageOffered: insurance coverage amount already offered
    struct SubCategoryInfo {
        bool isActive;
        string subCategoryName;
        string info;
        string logo;
        uint256 liquidity;
        uint256 subCategoryID;
        uint256 streamFlowRate;
        uint256 coverageOffered;
    }

    /// @notice collects specific epochs info
    /// startTime: start time of the specific epoch
    /// endTime: end time of the specific epoch
    /// riskPoolLiquidity: risk pool liquidity during the specific epoch
    /// riskPoolStreamRate: risk pool stream rate during the specific epoch
    /// liquidation: liquidation, if happened, in the specific epoch
    struct RiskPoolEpochInfo {
        uint256 startTime;
        uint256 endTime;
        uint256 riskPoolLiquidity; 
        uint256 riskPoolStreamRate; 
        uint256 liquidation;
    }

    /// Maps :: categoryID(uint256) => epoch(uint256)
    mapping(uint256 => uint256) public epoch;

    /// Maps :: categoryID(uint256) => categoryName(string)
    mapping(uint256 => string) public category;

    /// Maps :: categoryID(uint256) => subCategoryID(uint256)
    mapping(uint256 => uint256) public override subCategoryID;

    /// Maps :: categoryID(uint256) => subCategoryID(uint256) => SubCategoryInfo(struct)
    mapping (uint256 => mapping(uint256 => SubCategoryInfo)) public subCategoriesInfo;

    /// Maps :: categoryID(uint256) => subCategoryID(uint256) => epoch(uint256) => riskPoolCategory(uint256)
    /// If value is less than 10000, then risk-pool is community governed, whereas,
    /// if value is equal or greater than 10000, then non-community governed risk-pool.
    mapping (uint256 => mapping(uint256 => mapping(uint256 => uint256))) public epochRiskPoolCategory;

    /// Maps :: categoryID(uint256) => riskPoolCategory(uint256) => epoch(uint256) => RiskPoolEpochInfo(struct)
    mapping(uint256 => mapping(uint256 => mapping(uint256 => RiskPoolEpochInfo))) public versionableRiskPoolsInfo;

    function getVersionableRiskPoolsInfo(
        uint256 categoryID_, 
        uint256 riskPoolCategory, 
        uint256 epoch_
    ) external view returns(uint256, uint256, uint256, uint256, uint256) {
        RiskPoolEpochInfo memory riskPoolInfo = versionableRiskPoolsInfo[categoryID_][riskPoolCategory][epoch_];
        return (
            riskPoolInfo.startTime, 
            riskPoolInfo.endTime, 
            riskPoolInfo.riskPoolLiquidity, 
            riskPoolInfo.riskPoolStreamRate, 
            riskPoolInfo.liquidation
        );
    }


    function initialize(
        address addressBuySellSZT,
        address addressDAI,
        address addressSZT
    ) external initializer {
        buySellSZT = IBuySellSZT(addressBuySellSZT);
        tokenDAI = IERC20Upgradeable(addressDAI);
        tokenSZT = IERC20Upgradeable(addressSZT);
        __BaseUpgradeablePausable_init(_msgSender());
    }

    function init(
        address addressCFA_,
        address addressCoveragePool,
        address addressClaimGovernance
    ) external onlyAdmin {
        if (initVersion > 0) {
            revert InsuranceRegistry__ImmutableChangesError();
        }
        ++initVersion;
        addressCFA = addressCFA_;
        coveragePool = ICoveragePool(addressCoveragePool);
        claimGovernance = IClaimGovernance(addressClaimGovernance);
    }

    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }

    function addInsuranceProduct(string memory categoryName) external onlyAdmin {
        ++categoryID;
        category[categoryID] = categoryName;
        emit InsuranceProductAdded();
    }

    function addInsuranceCategory(
        uint256 categoryID_,
        string memory subCategoryName,
        string memory info,
        string memory logo,
        uint256 riskPoolCategory,
        uint256 streamFlowRate
        ) external onlyAdmin {
        ++subCategoryID[categoryID_];
        uint256 subCategoryID_ = subCategoryID[categoryID_];
        SubCategoryInfo storage subCategoryInfo = subCategoriesInfo[categoryID_][subCategoryID_];
        subCategoryInfo.isActive = true;
        subCategoryInfo.subCategoryName = subCategoryName;
        subCategoryInfo.info = info;
        subCategoryInfo.logo = logo;
        subCategoryInfo.liquidity = 0;
        subCategoryInfo.subCategoryID = subCategoryID[categoryID_];
        subCategoryInfo.coverageOffered = 0;
        subCategoryInfo.streamFlowRate = streamFlowRate;
        uint256 versionID = epoch[categoryID_];
        epochRiskPoolCategory[categoryID_][subCategoryID_][versionID] = riskPoolCategory;
    }

    function updateProtocolRiskPoolCategory(
        uint256 categoryID_, 
        uint256 subCategoryID_, 
        uint256 riskPoolCategory
    ) external onlyAdmin {
        (/*uint256 oldRiskPoolCategory*/, uint256 previousIncomingFlowRate, uint256 previousLiquiditySupplied) = _beforeUpdateVersionInformation(categoryID_, subCategoryID_);
        _afterUpdateVersionInformation(categoryID_, subCategoryID_, riskPoolCategory, previousIncomingFlowRate, previousLiquiditySupplied);
    }

    function liquidatePositions(
        uint256 categoryID_,
        uint256 subCategoryID_,
        uint256 liquidatedPercent,
        uint256 coverageAmount
    ) external onlyAdmin {
        (uint256 riskPoolCategory, uint256 previousIncomingFlowRate, uint256 previousLiquiditySupplied) = _beforeUpdateVersionInformation(categoryID_, subCategoryID_);
        ++epoch[categoryID_];
        uint256 newVersionID = epoch[categoryID_];
        RiskPoolEpochInfo storage newRiskPool = versionableRiskPoolsInfo[categoryID_][riskPoolCategory][newVersionID];
        newRiskPool.startTime = block.timestamp;
        newRiskPool.liquidation = 100 - liquidatedPercent;
        newRiskPool.riskPoolLiquidity = ((previousLiquiditySupplied * (100 - liquidatedPercent)) / 100);
        newRiskPool.riskPoolStreamRate = previousIncomingFlowRate;
        for(uint i = 1; i <= subCategoryID[categoryID_];) {
            if (
                (epochRiskPoolCategory[categoryID_][i][newVersionID - 1] == riskPoolCategory) &&
                (subCategoriesInfo[categoryID_][i].isActive)
            ) {
                epochRiskPoolCategory[categoryID_][i][newVersionID] = riskPoolCategory;
                subCategoriesInfo[categoryID_][i].liquidity = ((subCategoriesInfo[categoryID_][i].liquidity * (100 - liquidatedPercent)) / 100);
            }
            ++i;
        }
        subCategoriesInfo[categoryID_][subCategoryID_].coverageOffered -= coverageAmount;
    }

    function updateStreamFlowRate(
        uint256 categoryID_, 
        uint256 subCategoryID_, 
        uint256 newFlowRate
    ) external onlyAdmin {
        subCategoriesInfo[categoryID_][subCategoryID_].streamFlowRate = newFlowRate;
    }

    // coverage provided
    function addInsuranceLiquidity(
        uint256 categoryID_,
        uint256 subCategoryID_,
        uint256 liquiditySupplied
    ) external override returns(bool) {
        _onlyCoveragePool();
        (uint256 riskPoolCategory, uint256 previousIncomingFlowRate, uint256 previousLiquiditySupplied) = _beforeUpdateVersionInformation(categoryID_, subCategoryID_);
        _afterUpdateVersionInformation(categoryID_, subCategoryID_, riskPoolCategory, previousIncomingFlowRate, (previousLiquiditySupplied + liquiditySupplied));
        subCategoriesInfo[categoryID_][subCategoryID_].liquidity += liquiditySupplied;
        return true;
    }

    // coverage taken out
    function removeInsuranceLiquidity(
        uint256 categoryID_,
        uint256 subCategoryID_, 
        uint256 liquiditySupplied
    ) external override  returns(bool) {
        _onlyCoveragePool();
        (uint256 riskPoolCategory, uint256 previousIncomingFlowRate, uint256 previousLiquiditySupplied) = _beforeUpdateVersionInformation(categoryID_, subCategoryID_);
        uint256 SZTTokenCounter = buySellSZT.tokenCounter();
        (, uint256 amountCoveredInDAI) = buySellSZT.calculatePriceSZT((SZTTokenCounter - liquiditySupplied), SZTTokenCounter);
        _afterUpdateVersionInformation(categoryID_, subCategoryID_, riskPoolCategory, previousIncomingFlowRate, (previousLiquiditySupplied - amountCoveredInDAI));
        subCategoriesInfo[categoryID_][subCategoryID_].liquidity -= amountCoveredInDAI; 
        return true;
    }

    // purchase insurance
    function addCoverageOffered(
        uint256 categoryID_,
        uint256 subCategoryID_, 
        uint256 coverageAmount,
        uint256 incomingFlowRate
    ) external  returns(bool) {
        _onlyCFA();
        if (!ifEnoughLiquidity(categoryID_, coverageAmount, subCategoryID_)) {
            revert InsuranceRegistry__NotEnoughLiquidityError();
        }
        (uint256 riskPoolCategory, uint256 previousIncomingFlowRate, uint256 previousLiquiditySupplied) = _beforeUpdateVersionInformation(categoryID_, subCategoryID_);
        _afterUpdateVersionInformation(categoryID_, subCategoryID_, riskPoolCategory, (previousIncomingFlowRate + incomingFlowRate), previousLiquiditySupplied);
        subCategoriesInfo[categoryID_][subCategoryID_].coverageOffered += coverageAmount;
        return true;       
    }

    // insurance completed
    function removeCoverageOffered(
        uint256 categoryID_,
        uint256 subCategoryID_, 
        uint256 coverageAmount, 
        uint256 incomingFlowRate
    ) external returns(bool) {
        _onlyCFA();
        (uint256 riskPoolCategory, uint256 previousIncomingFlowRate, uint256 previousLiquiditySupplied) = _beforeUpdateVersionInformation(categoryID_, subCategoryID_);
        _afterUpdateVersionInformation(categoryID_, subCategoryID_, riskPoolCategory, (previousIncomingFlowRate - incomingFlowRate), previousLiquiditySupplied);
        subCategoriesInfo[categoryID_][subCategoryID_].coverageOffered -= coverageAmount; 
        return true;  
    }

    function claimAdded(
        uint256 categoryID_, 
        uint256 subCategoryID_
    ) external override returns(bool) {
        _onlyClaimGovernance();
        (uint256 riskPoolCategory, uint256 previousIncomingFlowRate, uint256 previousLiquiditySupplied) = _beforeUpdateVersionInformation(categoryID_, subCategoryID_);
        _afterUpdateVersionInformation(categoryID_, subCategoryID_, riskPoolCategory, previousIncomingFlowRate, previousLiquiditySupplied);
        return true;
    }

    function calculateUnderwriterBalance(
        uint256 categoryID_,
        uint256 subCategoryID_
    ) public view returns(uint256) {
        uint256 userBalance = 0;
        uint256 liquidatedAmount = 0;
        uint256 riskPoolCategory = 0;
        uint256 userPremiumEarned = 0;
        uint256 premiumEarnedFlowRate = 0;       
        (, uint256 startVersionID, ) = coveragePool.getUserInfo(_msgSender(), categoryID_, subCategoryID_);
        uint256 currVersion = epoch[categoryID_];
        for(uint256 i = startVersionID; i <= currVersion;) {
            /// this check ensures that for versions when this value is not present, the user balance will be previous epoch balance
            /// when user last interacted with the protocol
            userBalance = (
                coveragePool.underwritersBalance(_msgSender(), categoryID_, subCategoryID_, i) > 0 ? 
                coveragePool.underwritersBalance(_msgSender(), categoryID_, subCategoryID_, i) : userBalance
            );
            riskPoolCategory = epochRiskPoolCategory[categoryID_][subCategoryID_][i];
            RiskPoolEpochInfo memory versionableInfo = versionableRiskPoolsInfo[categoryID_][riskPoolCategory][i];
            liquidatedAmount += (userBalance - (userBalance * versionableInfo.liquidation) / 100);
            premiumEarnedFlowRate = versionableInfo.riskPoolStreamRate;            
            uint256 duration = versionableInfo.endTime - versionableInfo.startTime;
            userPremiumEarned += ((duration * userBalance * premiumEarnedFlowRate * PLATFORM_COST) / (100 * versionableInfo.riskPoolLiquidity));
            ++i;
        }
        userBalance -= liquidatedAmount;
        userBalance += userPremiumEarned;
        return userBalance;
    }

    function _beforeUpdateVersionInformation(
        uint256 categoryID_, 
        uint256 subCategoryID_
    ) internal returns(uint256, uint256, uint256) {
        uint256 versionID = epoch[categoryID_];
        uint256 riskPoolCategory = epochRiskPoolCategory[categoryID_][subCategoryID_][versionID];
        RiskPoolEpochInfo storage riskPool = versionableRiskPoolsInfo[categoryID_][riskPoolCategory][versionID];
        riskPool.endTime = block.timestamp;
        uint256 previousIncomingFlowRate = riskPool.riskPoolStreamRate;
        uint256 previousLiquiditySupplied = riskPool.riskPoolLiquidity;
        return (riskPoolCategory, previousIncomingFlowRate, previousLiquiditySupplied);
    }

    function _afterUpdateVersionInformation(
        uint256 categoryID_, 
        uint256 subCategoryID_, 
        uint256 riskPoolCategory,
        uint256 previousIncomingFlowRate, 
        uint256 previousLiquiditySupplied
    ) internal {
        ++epoch[categoryID_];
        uint256 versionID = epoch[categoryID_];
        RiskPoolEpochInfo storage riskPool = versionableRiskPoolsInfo[categoryID_][riskPoolCategory][versionID];
        riskPool.startTime = block.timestamp;
        riskPool.riskPoolLiquidity = previousLiquiditySupplied;
        riskPool.riskPoolStreamRate = previousIncomingFlowRate;
        epochRiskPoolCategory[categoryID_][subCategoryID_][versionID] = riskPoolCategory;
    }

    /// @notice function access restricted to the Constant Flow Agreement contract address calls only
    function _onlyCFA() private view {
        if(_msgSender() != addressCFA) {
            revert InsuranceRegistry__AccessRestricted();
        }
    }

    /// @notice function access restricted to the Claim Governance contract address calls only
    function _onlyClaimGovernance() private view {
        if(_msgSender() != address(claimGovernance)) {
            revert InsuranceRegistry__AccessRestricted();
        }
    }
    

    /// @notice function access restricted to the Coverage Pool contract address calls only
    function _onlyCoveragePool() private view {
        if(_msgSender() != address(coveragePool)) {
            revert InsuranceRegistry__AccessRestricted();
        }
    }

    function getVersionID(uint256 categoryID_) external view returns(uint256) {
        return epoch[categoryID_];
    }   

    function getInsuranceInfo(
        uint256 categoryID_, 
        uint256 subCategoryID_
    ) external view returns(bool, string memory, string memory, string memory, uint256, uint256, uint256) {
        SubCategoryInfo storage insuranceInfo = subCategoriesInfo[categoryID_][subCategoryID_];
        return (insuranceInfo.isActive, 
                insuranceInfo.subCategoryName, 
                insuranceInfo.info,
                insuranceInfo.logo,
                insuranceInfo.liquidity, 
                insuranceInfo.streamFlowRate,
                insuranceInfo.coverageOffered
        );
    }

    function getProtocolRiskCategory(uint256 categoryID_, uint256 subCategoryID_, uint256 version_) external view returns (uint256) {
        return epochRiskPoolCategory[categoryID_][subCategoryID_][version_];
    }

    function getStreamFlowRate(uint256 categoryID_, uint256 subCategoryID_) external view returns(uint256) {
        return subCategoriesInfo[categoryID_][subCategoryID_].streamFlowRate;
    }

    
    function ifEnoughLiquidity(uint256 categoryID_, uint256 insuredAmount, uint256 subCategoryID_) public view returns(bool) {
        bool isTrue = subCategoriesInfo[categoryID_][subCategoryID_].liquidity >= (subCategoriesInfo[categoryID_][subCategoryID_].coverageOffered + insuredAmount);
        return isTrue;
    }

    function getPoolExpectedPremium(uint256 categoryID_, uint256 riskPoolCategory, uint256 version_) external view returns(uint256) {
        return versionableRiskPoolsInfo[categoryID_][riskPoolCategory][version_].riskPoolStreamRate;
    }

    function getPoolLiquidity(uint256 categoryID_, uint256 riskPoolCategory, uint256 version_) external view returns (uint256) {
        return versionableRiskPoolsInfo[categoryID_][riskPoolCategory][version_].riskPoolLiquidity;
    }

    function getPoolLiquidationPercent(uint256 categoryID_, uint256 riskPoolCategory, uint256 version_) public view returns(uint256) {
        return versionableRiskPoolsInfo[categoryID_][riskPoolCategory][version_].liquidation;
    }

    function getLatestCategoryID() external view returns(uint256) {
        return categoryID;
    }
    
    function getLatestSubCategoryID(uint256 categoryID_) external view returns(uint256) {
        return subCategoryID[categoryID_];
    }
}