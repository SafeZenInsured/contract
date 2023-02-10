// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/// @title Insurance Registry Contract
/// @author Anshik Bansal <anshik@safezen.finance>

/// Importing required interfaces
import "./../../interfaces/IBuySellSZT.sol";
import "./../../interfaces/ICoveragePool.sol";
import "./../../interfaces/IInsuranceRegistry.sol";
import "./../../interfaces/IClaimGovernance.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

/// Importing required contracts
import "./../../BaseUpgradeablePausable.sol";

/// Report any bug or issues at:
/// @custom:security-contact anshik@safezen.finance
contract InsuranceRegistry is IInsuranceRegistry, BaseUpgradeablePausable {
    /// _initVersion: counter to initialize the init one-time function, max value can be 1.
    /// _categoryID: insurance category, e.g., stablecoin depeg insurance.
    /// PLATFORM_COST: platform fee on the profit earned
    /// _addressCFA:address of the Constant Flow Agreement contract interface
    uint256 private _initVersion;
    uint256 private _categoryID;
    uint256 private constant PLATFORM_COST = 90;
    address private _addressCFA;

    
    /// _tokenDAI: DAI ERC20 token interface
    /// _tokenSZT: SZT ERC20 token interface
    /// _buySellSZT:Buy Sell SZT contract interface
    /// _coveragePool: Coverage Pool contract interface
    IERC20 private _tokenDAI;
    IERC20 private _tokenSZT;
    IBuySellSZT private _buySellSZT;
    ICoveragePool private _coveragePool;
    IClaimGovernance private _claimGovernance;

    /// @dev collects info about the insurance subcategories, e.g., USDC depeg coverage, DAI depeg coverage.
    /// isActive: checks whether insurance given subcategory is active or not.
    /// subCategoryName: insurance subcategory title
    /// info: insurance subcategory info, e.g., algorithmic stablecoin, etc.
    /// liquidity: insurance maximum coverage amount that can be offered
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
        uint256 startTime; // at the start
        uint256 endTime;  // at the end
        uint256 riskPoolLiquidity; // at the start
        uint256 riskPoolStreamRate; // at the start
        uint256 liquidation; // if needed
    }

    /// Maps :: categoryID(uint256) => epoch(uint256)
    mapping(uint256 => uint256) public epoch;

    /// Maps :: categoryID(uint256) => subCategoryID(uint256)
    mapping(uint256 => uint256) public subCategoryID;

    /// Maps :: categoryID(uint256) => subCategoryID(uint256) => SubCategoryInfo(struct)
    mapping (uint256 => mapping(uint256 => SubCategoryInfo)) public subCategoriesInfo;

    /// Maps :: categoryID(uint256) => subCategoryID(uint256) => epoch(uint256) => riskPoolCategory(uint256)
    /// If value is less than 10000, then risk-pool is community governed, whereas,
    /// if value is equal or greater than 10000, then non-community governed risk-pool.
    mapping (uint256 => mapping(uint256 => mapping(uint256 => uint256))) public epochRiskPoolCategory;

    /// Maps :: categoryID(uint256) => riskPoolCategory(uint256) => epoch(uint256) => RiskPoolEpochInfo(struct)
    mapping(uint256 => mapping(uint256 => mapping(uint256 => RiskPoolEpochInfo))) public versionableRiskPoolsInfo;

    /// @notice function access restricted to the Constant Flow Agreement contract address calls only
    modifier onlyCFA() {
        require(_msgSender() == _addressCFA);
        _;
    }

    /// @notice function access restricted to the Claim Governance contract address calls only
    modifier onlyClaimGovernance() {
        require(_msgSender() == address(_claimGovernance));
        _;
    }

    /// @notice function access restricted to the Coverage Pool contract address calls only
    modifier onlyCoveragePool() {
        require(_msgSender() == address(_coveragePool));
        _;
    }

    function initialize(
        address buySellSZTCA,
        address tokenAddressDAI,
        address tokenAddressSZT
    ) external initializer {
        _buySellSZT = IBuySellSZT(buySellSZTCA);
        _tokenDAI = IERC20(tokenAddressDAI);
        _tokenSZT = IERC20(tokenAddressSZT);
        __BaseUpgradeablePausable_init(_msgSender());
    }

    function init(
        address CFA,
        address coveragePoolAddress,
        address addressClaimGovernance
    ) external onlyAdmin {
        if (_initVersion > 0) {
            revert InsuranceRegistry__ImmutableChangesError();
        }
        ++_initVersion;
        _addressCFA = CFA;
        _coveragePool = ICoveragePool(coveragePoolAddress);
        _claimGovernance = IClaimGovernance(addressClaimGovernance);
    }

    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }

    function addInsuranceProduct() external onlyAdmin {
        ++_categoryID;
    }

    function addInsuranceCategory(
        uint256 categoryID,
        string memory subCategoryName,
        string memory info,
        string memory logo,
        uint256 riskPoolCategory,
        uint256 streamFlowRate
        ) external onlyAdmin {
        ++subCategoryID[categoryID];
        uint256 subCategoryID_ = subCategoryID[categoryID];
        SubCategoryInfo storage subCategoryInfo = subCategoriesInfo[categoryID][subCategoryID_];
        subCategoryInfo.isActive = true;
        subCategoryInfo.subCategoryName = subCategoryName;
        subCategoryInfo.info = info;
        subCategoryInfo.logo = logo;
        subCategoryInfo.liquidity = 0;
        subCategoryInfo.subCategoryID = subCategoryID[categoryID];
        subCategoryInfo.coverageOffered = 0;
        subCategoryInfo.streamFlowRate = streamFlowRate;
        uint256 versionID = epoch[categoryID];
        epochRiskPoolCategory[categoryID][subCategoryID_][versionID] = riskPoolCategory;
    }

    function updateProtocolRiskPoolCategory(
        uint256 categoryID, 
        uint256 subCategoryID_, 
        uint256 riskPoolCategory
    ) external onlyAdmin {
        (/*uint256 oldRiskPoolCategory*/, uint256 previousIncomingFlowRate, uint256 previousLiquiditySupplied) = _beforeUpdateVersionInformation(categoryID, subCategoryID_);
        _afterUpdateVersionInformation(categoryID, subCategoryID_, riskPoolCategory, previousIncomingFlowRate, previousLiquiditySupplied);
    }

    function liquidatePositions(
        uint256 categoryID,
        uint256 subCategoryID_,
        uint256 liquidatedPercent,
        uint256 coverageAmount
    ) external onlyAdmin {
        (uint256 riskPoolCategory, uint256 previousIncomingFlowRate, uint256 previousLiquiditySupplied) = _beforeUpdateVersionInformation(categoryID, subCategoryID_);
        ++epoch[categoryID];
        uint256 newVersionID = epoch[categoryID];
        RiskPoolEpochInfo storage newRiskPool = versionableRiskPoolsInfo[categoryID][riskPoolCategory][newVersionID];
        newRiskPool.startTime = block.timestamp;
        newRiskPool.liquidation = 100 - liquidatedPercent;
        newRiskPool.riskPoolLiquidity = ((previousLiquiditySupplied * (100 - liquidatedPercent)) / 100);
        newRiskPool.riskPoolStreamRate = previousIncomingFlowRate;
        for(uint i = 1; i <= subCategoryID[categoryID];) {
            if (
                (epochRiskPoolCategory[categoryID][i][newVersionID - 1] == riskPoolCategory) &&
                (subCategoriesInfo[categoryID][i].isActive)
            ) {
                epochRiskPoolCategory[categoryID][i][newVersionID] = riskPoolCategory;
                subCategoriesInfo[categoryID][i].liquidity = ((subCategoriesInfo[categoryID][i].liquidity * (100 - liquidatedPercent)) / 100);
            }
            ++i;
        }
        subCategoriesInfo[categoryID][subCategoryID_].coverageOffered -= coverageAmount;
    }

    function updateStreamFlowRate(
        uint256 categoryID, 
        uint256 subCategoryID_, 
        uint256 newFlowRate
    ) external onlyAdmin {
        subCategoriesInfo[categoryID][subCategoryID_].streamFlowRate = newFlowRate;
    }

    // coverage provided
    function addInsuranceLiquidity(
        uint256 categoryID,
        uint256 subCategoryID_,
        uint256 liquiditySupplied
    ) external override onlyCoveragePool returns(bool) {
        (uint256 riskPoolCategory, uint256 previousIncomingFlowRate, uint256 previousLiquiditySupplied) = _beforeUpdateVersionInformation(categoryID, subCategoryID_);
        _afterUpdateVersionInformation(categoryID, subCategoryID_, riskPoolCategory, previousIncomingFlowRate, (previousLiquiditySupplied + liquiditySupplied));
        subCategoriesInfo[categoryID][subCategoryID_].liquidity += liquiditySupplied;
        return true;
    }

    // coverage taken out
    function removeInsuranceLiquidity(
        uint256 categoryID,
        uint256 subCategoryID_, 
        uint256 liquiditySupplied
    ) external override onlyCoveragePool returns(bool) {
        (uint256 riskPoolCategory, uint256 previousIncomingFlowRate, uint256 previousLiquiditySupplied) = _beforeUpdateVersionInformation(categoryID, subCategoryID_);
        uint256 SZTTokenCounter = _buySellSZT.getTokenCounter();
        (, uint256 amountCoveredInDAI) = _buySellSZT.calculatePriceSZT((SZTTokenCounter - liquiditySupplied), SZTTokenCounter);
        _afterUpdateVersionInformation(categoryID, subCategoryID_, riskPoolCategory, previousIncomingFlowRate, (previousLiquiditySupplied - amountCoveredInDAI));
        subCategoriesInfo[categoryID][subCategoryID_].liquidity -= amountCoveredInDAI; 
        return true;
    }

    // purchase insurance
    function addCoverageOffered(
        uint256 categoryID,
        uint256 subCategoryID_, 
        uint256 coverageAmount,
        uint256 incomingFlowRate
    ) external onlyCFA returns(bool) {
        if (!ifEnoughLiquidity(categoryID, coverageAmount, subCategoryID_)) {
            revert InsuranceRegistry__NotEnoughLiquidityError();
        }
        (uint256 riskPoolCategory, uint256 previousIncomingFlowRate, uint256 previousLiquiditySupplied) = _beforeUpdateVersionInformation(categoryID, subCategoryID_);
        _afterUpdateVersionInformation(categoryID, subCategoryID_, riskPoolCategory, (previousIncomingFlowRate + incomingFlowRate), previousLiquiditySupplied);
        subCategoriesInfo[categoryID][subCategoryID_].coverageOffered += coverageAmount;
        return true;       
    }

    // insurance completed
    function removeCoverageOffered(
        uint256 categoryID,
        uint256 subCategoryID_, 
        uint256 coverageAmount, 
        uint256 incomingFlowRate
    ) external onlyCFA returns(bool) {
        (uint256 riskPoolCategory, uint256 previousIncomingFlowRate, uint256 previousLiquiditySupplied) = _beforeUpdateVersionInformation(categoryID, subCategoryID_);
        _afterUpdateVersionInformation(categoryID, subCategoryID_, riskPoolCategory, (previousIncomingFlowRate - incomingFlowRate), previousLiquiditySupplied);
        subCategoriesInfo[categoryID][subCategoryID_].coverageOffered -= coverageAmount; 
        return true;  
    }

    function claimAdded(
        uint256 categoryID, 
        uint256 subCategoryID_
    ) external override onlyClaimGovernance returns(bool) {
        (uint256 riskPoolCategory, uint256 previousIncomingFlowRate, uint256 previousLiquiditySupplied) = _beforeUpdateVersionInformation(categoryID, subCategoryID_);
        _afterUpdateVersionInformation(categoryID, subCategoryID_, riskPoolCategory, previousIncomingFlowRate, previousLiquiditySupplied);
        return true;
    }
    
    function calculateUnderwriterBalance(
        uint256 categoryID,
        uint256 subCategoryID_
    ) external view returns(uint256) {
        uint256 userBalance = 0;
        uint256[] memory activeVersionID = _coveragePool.getUnderwriterActiveVersionID(categoryID, subCategoryID_);
        uint256 startVersionID = activeVersionID[0];
        uint256 premiumEarnedFlowRate = 0;
        uint256 userPremiumEarned = 0;
        uint256 riskPoolCategory = epochRiskPoolCategory[categoryID][subCategoryID_][startVersionID];
        uint256 counter = 0;
        for(uint256 i = startVersionID; i <= epoch[subCategoryID_];) {
            if(activeVersionID[counter] == i) {
                if (_coveragePool.getUnderWriterDepositedBalance(categoryID, subCategoryID_, i) > 0) {
                    userBalance += _coveragePool.getUnderWriterDepositedBalance(categoryID, subCategoryID_, i);
                }
                else {
                    userBalance -= _coveragePool.getUnderWriterWithdrawnBalance(categoryID, subCategoryID_, i);
                }
                ++counter;
            }
            riskPoolCategory = epochRiskPoolCategory[categoryID][subCategoryID_][i];
            RiskPoolEpochInfo storage riskPool = versionableRiskPoolsInfo[categoryID][riskPoolCategory][i];
            userBalance = (userBalance * riskPool.liquidation) / 100;
            premiumEarnedFlowRate = riskPool.riskPoolStreamRate;            
            uint256 duration = riskPool.endTime - riskPool.startTime;
            userPremiumEarned += ((duration * userBalance * premiumEarnedFlowRate * PLATFORM_COST)/ (100 * riskPool.riskPoolLiquidity));
            ++i;
        }
        userBalance += userPremiumEarned;
        return userBalance;
    }

    function _beforeUpdateVersionInformation(
        uint256 categoryID, 
        uint256 subCategoryID_
    ) internal returns(uint256, uint256, uint256) {
        uint256 versionID = epoch[categoryID];
        uint256 riskPoolCategory = epochRiskPoolCategory[categoryID][subCategoryID_][versionID];
        RiskPoolEpochInfo storage riskPool = versionableRiskPoolsInfo[categoryID][riskPoolCategory][versionID];
        riskPool.endTime = block.timestamp;
        uint256 previousIncomingFlowRate = riskPool.riskPoolStreamRate;
        uint256 previousLiquiditySupplied = riskPool.riskPoolLiquidity;
        return (riskPoolCategory, previousIncomingFlowRate, previousLiquiditySupplied);
    }

    function _afterUpdateVersionInformation(
        uint256 categoryID, 
        uint256 subCategoryID_, 
        uint256 riskPoolCategory,
        uint256 previousIncomingFlowRate, 
        uint256 previousLiquiditySupplied
    ) internal {
        ++epoch[categoryID];
        uint256 versionID = epoch[categoryID];
        RiskPoolEpochInfo storage riskPool = versionableRiskPoolsInfo[categoryID][riskPoolCategory][versionID];
        riskPool.startTime = block.timestamp;
        riskPool.riskPoolLiquidity = previousLiquiditySupplied;
        riskPool.riskPoolStreamRate = previousIncomingFlowRate;
        epochRiskPoolCategory[categoryID][subCategoryID_][versionID] = riskPoolCategory;
    }

    function getVersionID(uint256 categoryID) external view returns(uint256) {
        return epoch[categoryID];
    }   

    function getInsuranceInfo(
        uint256 categoryID, 
        uint256 subCategoryID_
    ) external view returns(bool, string memory, string memory, string memory, uint256, uint256, uint256) {
        SubCategoryInfo storage insuranceInfo = subCategoriesInfo[categoryID][subCategoryID_];
        return (insuranceInfo.isActive, 
                insuranceInfo.subCategoryName, 
                insuranceInfo.info,
                insuranceInfo.logo,
                insuranceInfo.liquidity, 
                insuranceInfo.streamFlowRate,
                insuranceInfo.coverageOffered
        );
    }

    function getProtocolRiskCategory(uint256 categoryID, uint256 subCategoryID_, uint256 version_) external view returns (uint256) {
        return epochRiskPoolCategory[categoryID][subCategoryID_][version_];
    }

    function getStreamFlowRate(uint256 categoryID, uint256 subCategoryID_) external view returns(uint256) {
        return subCategoriesInfo[categoryID][subCategoryID_].streamFlowRate;
    }

    
    function ifEnoughLiquidity(uint256 categoryID, uint256 insuredAmount, uint256 subCategoryID_) public view returns(bool) {
        bool isTrue=  subCategoriesInfo[categoryID][subCategoryID_].liquidity >= (subCategoriesInfo[categoryID][subCategoryID_].coverageOffered + insuredAmount);
        return isTrue;
    }

    function getPoolExpectedPremium(uint256 categoryID, uint256 riskPoolCategory, uint256 version_) external view returns(uint256) {
        return versionableRiskPoolsInfo[categoryID][riskPoolCategory][version_].riskPoolStreamRate;
    }

    function getPoolLiquidity(uint256 categoryID, uint256 riskPoolCategory, uint256 version_) external view returns (uint256) {
        return versionableRiskPoolsInfo[categoryID][riskPoolCategory][version_].riskPoolLiquidity;
    }

    function getPoolLiquidationPercent(uint256 categoryID, uint256 riskPoolCategory, uint256 version_) public view returns(uint256) {
        return versionableRiskPoolsInfo[categoryID][riskPoolCategory][version_].liquidation;
    }

    function getLatestCategoryID() external view returns(uint256) {
        return _categoryID;
    }
    
    function getLatestSubCategoryID(uint256 categoryID) external view returns(uint256) {
        return subCategoryID[categoryID];
    }
}