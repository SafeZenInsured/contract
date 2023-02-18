// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/// @title Coverage Pool Contract
/// @author Anshik Bansal <anshik@safezen.finance>

/// Importing required interfaces
import "./../../interfaces/IBuySellSZT.sol";
import "./../../interfaces/ICoveragePool.sol";
import "./../../interfaces/IInsuranceRegistry.sol";
import "@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";


/// Importing required contracts
import "./../../BaseUpgradeablePausable.sol";

/// Report any bug or issues at:
/// @custom:security-contact anshik@safezen.finance
contract CoveragePool is ICoveragePool, BaseUpgradeablePausable {
    
    // ::::::::::::::::: STATE VARIABLES AND DECLARATIONS :::::::::::::::: //
    
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeERC20Upgradeable for IERC20PermitUpgradeable;

    /// initVersion: counter to initialize the init one-time function, max value can be 1.
    /// waitingTime: staked token withdrawal waiting time
    /// totalTokensStaked: total amount of SZT tokens staked to underwrite insurance
    uint256 public tokenID;
    uint256 public initVersion;
    uint256 public waitingTime;
    uint256 public minCoveragePoolAmount;
    uint256 public override totalTokensStaked;

    
    /// tokenSZT: SZT ERC20 token
    /// _buySellContract: Buy Sell SZT Contract
    /// insuranceRegistry: Insurance Registry Contract
    IERC20Upgradeable public immutable tokenSZT;
    IERC20Upgradeable public immutable tokenDAI;
    IERC20PermitUpgradeable public immutable tokenPermitDAI;
    IBuySellSZT public immutable buySellSZT;
    IInsuranceRegistry public insuranceRegistry;

    /// @dev collects underwriters' withdrawal request data
    /// @param ifTimerStarted: checks if the withdrawal waiting timer been activated by underwriter or not 
    /// @param tokenCountSZT: amount of SZT token requested for withdrawal
    /// @param canWithdrawTime: time after which the user can withdraw the requested amount of SZT token
    struct WithdrawWaitPeriod{
        bool ifTimerStarted;
        uint256 tokenCountSZT;
        uint256 canWithdrawTime;
    }

    /// @dev collects underwriters' global coverage offered info
    /// @param isActiveInvested: checks if the underwriter has 
    /// @param startVersionBlock: stores underwriters' first version block number
    struct UserInfo {
        bool isActiveInvested;
        uint256 depositedAmount;
        uint256 startVersionBlock;
        uint256 previousUserEpoch;
    }

    /// @dev collects underwriters' account balance incl. deposits and withdrawals
    /// @param depositedAmount: amount of SZT tokens deposited
    /// @param withdrawnAmount: amount of SZT tokens withdrawn
    struct BalanceInfo {
        uint256 depositedAmount;
        uint256 withdrawnAmount;
    }

    mapping(uint256 => address) public override permissionedTokens;

    /// @dev mapping to store underwriters' global coverage offered portfolio
    /// maps userAddress => userPoolBalanceSZT
    mapping (address => uint256) public override userPoolBalanceSZT;

    /// record the user info, i.e. if the user has invested in a particular protocol
    /// user address => categoryID => subCategoryID
    mapping(address => mapping(uint256 => mapping(uint256 => UserInfo))) private usersInfo;

    // user address => categoryID => subCategoryID => withdrawal wait period
    mapping(address => mapping(uint256 => mapping(uint256 => WithdrawWaitPeriod))) private checkWaitTime;
    // user address => categoryID => subCategoryID => version => underwriterinfo
    mapping(address => mapping(uint256 => mapping(uint256 => mapping(uint256 => BalanceInfo)))) private underwritersBalance;

    // ::::::::::::::::::::::::::: CONSTRUCTOR ::::::::::::::::::::::::::: //

    constructor(address addressSZT, address addressBuySellSZT, address addressDAI) {
        tokenSZT = IERC20Upgradeable(addressSZT);
        buySellSZT = IBuySellSZT(addressBuySellSZT);
        tokenDAI = IERC20Upgradeable(addressDAI);
        tokenPermitDAI = IERC20PermitUpgradeable(addressDAI);
    }

    // ::::::::::::::::::::::::: ADMIN FUNCTIONS ::::::::::::::::::::::::: //

    /// @dev one-time function aims to initialize the contract
    /// @dev MUST revert if called more than once.
    /// @param insuranceRegAddress: address of the Insurance Registry contract
    function initialize(address insuranceRegAddress) external initializer {
        insuranceRegistry = IInsuranceRegistry(insuranceRegAddress);
        waitingTime = 20;
        minCoveragePoolAmount = 1e18;
        totalTokensStaked = 0;
        __BaseUpgradeablePausable_init(_msgSender());

    }

    /// @dev this function aims to update the required minimum coverage amount for underwriters' deposits
    /// @param valueInSZT: amount of SZT token
    function updateMinCoveragePoolAmount(uint256 valueInSZT) external onlyAdmin {
        minCoveragePoolAmount = valueInSZT;
        emit UpdatedMinCoveragePoolAmount();
    }

    /// @dev this function aims to update the underwriters' withdrawal waiting delay
    /// @param timeInDays: 3-4 days will be kept as default.
    /// [PRODUCTION TODO: waitingTime = timeInDays * 1 days;]
    function updateWaitingPeriodTime(uint256 timeInDays) external onlyAdmin {
        waitingTime = timeInDays * 1 seconds;
        emit UpdatedWaitingPeriod(timeInDays);
    }

    function addTokenAddress(address addressToken) external onlyAdmin {
        if(addressToken == address(0)) {
            revert CoveragePool__ZeroAddressInputError();
        }
        ++tokenID;
        permissionedTokens[tokenID] = addressToken;
    }

    /// @notice to pause the certain functions within the contract
    function pause() external onlyAdmin {
        _pause();
    }

    /// @notice to unpause the certain functions paused earlier within the contract
    function unpause() external onlyAdmin {
        _unpause();
    }

    // :::::::::::::::::::::::: WRITING FUNCTIONS :::::::::::::::::::::::: //
    
    // :::::::::::::::::::::::: EXTERNAL FUNCTIONS ::::::::::::::::::::::: //
    
    /// @dev this function aims to add the coverage offered by the underwriters'
    /// @param amountInSZT: amount of SZT token
    /// @param categoryID: insurance category, e.g., stablecoin depeg insurance.
    /// @param subCategoryID: insurance sub-category, e.g., USDC depeg coverage, DAI depeg coverage.
    /// @param deadline: DAI ERC20 token permit deadline
    /// @param permitV: DAI ERC20 token permit signature (value v)
    /// @param permitR: DAI ERC20 token permit signature (value r)
    /// @param permitS: DAI ERC20 token permit signature (value s)
    function underwrite(
        uint256 amountInSZT, 
        uint256 categoryID, 
        uint256 subCategoryID,
        uint deadline, 
        uint8 permitV, 
        bytes32 permitR, 
        bytes32 permitS
    ) public override nonReentrant returns(bool) {
        if (amountInSZT < minCoveragePoolAmount) {
            revert CoveragePool__NotAMinimumPoolAmountError();
        }
        uint256 tokenCounter = buySellSZT.tokenCounter();
        (/*uint256 amountPerToken*/, uint256 amountPaidInDAI) = buySellSZT.calculatePriceSZT(
            tokenCounter, (tokenCounter + amountInSZT)
        );
        if (tokenDAI.balanceOf(_msgSender()) < amountPaidInDAI) {
            revert CoveragePool__LowAmountError();
        }
        uint256 currVersion = insuranceRegistry.getVersionID(categoryID) + 1;
        uint256 userPreviousEpoch = usersInfo[_msgSender()][categoryID][subCategoryID].previousUserEpoch;
        underwritersBalance[_msgSender()][categoryID][subCategoryID][currVersion].depositedAmount = (
            underwritersBalance[_msgSender()][categoryID][subCategoryID][userPreviousEpoch].depositedAmount + amountInSZT);
        
        totalTokensStaked += amountInSZT;
        UserInfo storage userInfo = usersInfo[_msgSender()][categoryID][subCategoryID];
        if (!userInfo.isActiveInvested) {
            userInfo.startVersionBlock = currVersion;
            userInfo.isActiveInvested = true;
        }
        userInfo.depositedAmount += amountInSZT;
        userPoolBalanceSZT[_msgSender()] += amountInSZT;
        insuranceRegistry.addInsuranceLiquidity(categoryID, subCategoryID, amountPaidInDAI);
        tokenPermitDAI.safePermit(_msgSender(), address(this), amountPaidInDAI, deadline, permitV, permitR, permitS);
        tokenDAI.safeTransferFrom(_msgSender(), address(buySellSZT), amountPaidInDAI);
        bool buySuccess = buySellSZT.buySZTToken(_msgSender(), amountInSZT);
        if (!buySuccess) {
            revert CoveragePool__TransactionFailedError();
        }
        emit UnderwritePool(_msgSender(), categoryID, subCategoryID, amountInSZT);
        return true;
    }
    
    /// @dev this function aims to activate the SZT token withdrawal timer
    /// @param value: amount of SZT ERC20 token
    /// @param categoryID: insurance category, e.g., stablecoin depeg insurance.
    /// @param subCategoryID: insurance sub-category, e.g., USDC depeg coverage, DAI depeg coverage.
    function activateWithdrawalTimer(
        uint256 value, 
        uint256 categoryID, 
        uint256 subCategoryID
    ) external override returns(bool) {
        if (
            (!(checkWaitTime[_msgSender()][categoryID][subCategoryID].ifTimerStarted)) || 
            (checkWaitTime[_msgSender()][categoryID][subCategoryID].tokenCountSZT < value)
        ) {
            WithdrawWaitPeriod storage waitingTimeCountdown = checkWaitTime[_msgSender()][categoryID][subCategoryID];
            waitingTimeCountdown.ifTimerStarted = true;
            waitingTimeCountdown.tokenCountSZT = value;
            waitingTimeCountdown.canWithdrawTime = waitingTime + block.timestamp;
            return true;
        }
        return false;
    }
    
    /// @dev this function aims to reduce the coverage offered by the underwriters'
    /// @param value: amount of SZT token
    /// @param categoryID: insurance category, e.g., stablecoin depeg insurance.
    /// @param subCategoryID: insurance sub-category, e.g., USDC depeg coverage, DAI depeg coverage.
    /// @param deadline: GSZT ERC20 token permit deadline
    /// @param permitV: GSZT ERC20 token permit signature (value v)
    /// @param permitR: GSZT ERC20 token permit signature (value r)
    /// @param permitS: GSZT ERC20 token permit signature (value s)
    function withdraw(
        uint256 tokenID_,
        uint256 value, 
        uint256 categoryID, 
        uint256 subCategoryID,
        uint256 deadline, 
        uint8 permitV, 
        bytes32 permitR, 
        bytes32 permitS
    ) external override nonReentrant returns(bool) {
        uint256 userBalance = insuranceRegistry.calculateUnderwriterBalance(categoryID, subCategoryID);
        WithdrawWaitPeriod storage waitTime = checkWaitTime[_msgSender()][categoryID][subCategoryID];
        if (
            (userBalance < value) || 
            (block.timestamp < waitTime.canWithdrawTime) || 
            (value > waitTime.tokenCountSZT)
        ) {
            revert CoveragePool__TransactionFailedError();
        }
        uint256 currVersion = insuranceRegistry.getVersionID(categoryID) + 1;
        underwritersBalance[_msgSender()][categoryID][subCategoryID][currVersion].withdrawnAmount += value;
        waitTime.tokenCountSZT -= value;
        if (waitTime.tokenCountSZT == value) {
            waitTime.ifTimerStarted = false;
        }
        totalTokensStaked -= value;
        userPoolBalanceSZT[_msgSender()] -= value;
        usersInfo[_msgSender()][categoryID][subCategoryID].depositedAmount -= value;
        bool removeSuccess = insuranceRegistry.removeInsuranceLiquidity(subCategoryID, subCategoryID, value);
        bool sellSuccess = buySellSZT.sellSZTToken(_msgSender(), value, tokenID_, deadline, permitV, permitR, permitS);
        tokenSZT.safeTransfer(address(buySellSZT), value);
        if (!removeSuccess || !sellSuccess) {
            revert CoveragePool__TransactionFailedError();
        }
        emit PoolWithdrawn(_msgSender(), subCategoryID, subCategoryID, value);
        return true;
    }

    /// @notice this function returns the versions aka epoch when user performed deposit or withdrawal txn
    /// @param categoryID: insurance category, e.g., stablecoin depeg insurance.
    /// @param subCategoryID: insurance sub-category, e.g., USDC depeg coverage, DAI depeg coverage.
    function getUnderwriterActiveVersionID(
        uint256 categoryID, 
        uint256 subCategoryID
    ) external view returns(uint256[] memory) {
        uint256 activeCount = 0;
        uint256 userStartVersion = usersInfo[_msgSender()][categoryID][subCategoryID].startVersionBlock;
        uint256 currVersion =  insuranceRegistry.getVersionID(categoryID);
        for(uint256 i = userStartVersion; i <= currVersion;) {
            if (underwritersBalance[_msgSender()][categoryID][subCategoryID][i].depositedAmount > 0) {
                ++activeCount;
            }
            if (underwritersBalance[_msgSender()][categoryID][subCategoryID][i].withdrawnAmount > 0) {
                ++activeCount;
            }
            ++i;
        }
        uint256[] memory activeVersionID = new uint256[](activeCount);
        uint256 counter = 0;
        for(uint i = userStartVersion; i <= currVersion;) {
            BalanceInfo storage underwriterBalanceInfo = underwritersBalance[_msgSender()][categoryID][subCategoryID][i];
            if (underwriterBalanceInfo.depositedAmount > 0) {
                activeVersionID[counter] = i;
            }
            if (underwriterBalanceInfo.withdrawnAmount > 0) {
                activeVersionID[counter] = i;
            }
            ++counter;
            ++i;
        }
        return activeVersionID;
    }

    /// @notice this function returns user deposited amount for a particular epoch 
    
    function getUnderWriterDepositedBalance(
    ) external view {
        }

    /// @notice this function returns user withdrawn amount for a particular epoch
    function getUnderWriterWithdrawnBalance(
    ) external view {
    }

    /// @notice this function returns user deposited amount for a particular subcategory insurance
    function getUserCoveragePoolAmount(
    ) external view {
    }
}