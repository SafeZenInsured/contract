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
    /// _initVersion: counter to initialize the init one-time function, max value can be 1.
    /// _waitingTime: staked token withdrawal waiting time
    /// totalTokensStaked: total amount of SZT tokens staked to underwrite insurance
    uint256 private _initVersion;
    uint256 private _waitingTime;
    uint256 private _minCoveragePoolAmount;
    uint256 public override totalTokensStaked;

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeERC20Upgradeable for IERC20PermitUpgradeable;

    /// _tokenSZT: SZT ERC20 token
    /// _buySellContract: Buy Sell SZT Contract
    /// _insuranceRegistry: Insurance Registry Contract
    IERC20Upgradeable private immutable _tokenSZT;
    IERC20Upgradeable private immutable _tokenDAI;
    IERC20PermitUpgradeable private immutable _tokenPermitDAI;
    IBuySellSZT private immutable _buySellSZT;
    IInsuranceRegistry private _insuranceRegistry;

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
        uint256 startVersionBlock;
    }

    /// @dev collects underwriters' account balance incl. deposits and withdrawals
    /// @param depositedAmount: amount of SZT tokens deposited
    /// @param withdrawnAmount: amount of SZT tokens withdrawn
    struct BalanceInfo {
        uint256 depositedAmount;
        uint256 withdrawnAmount;
    }

    /// @dev mapping to store underwriters' global coverage offered portfolio
    /// maps userAddress => userPoolBalanceSZT
    mapping (address => uint256) private userPoolBalanceSZT;

    /// record the user info, i.e. if the user has invested in a particular protocol
    /// user address => categoryID => subCategoryID
    mapping(address => mapping(uint256 => mapping(uint256 => UserInfo))) private usersInfo;

    // user address => categoryID => subCategoryID => withdrawal wait period
    mapping(address => mapping(uint256 => mapping(uint256 => WithdrawWaitPeriod))) private checkWaitTime;
    // user address => categoryID => subCategoryID => version => underwriterinfo
    mapping(address => mapping(uint256 => mapping(uint256 => mapping(uint256 => BalanceInfo)))) private underwritersBalance;

    constructor(address addressSZT, address addressBuySellSZT, address tokenDAI) {
        _tokenSZT = IERC20Upgradeable(addressSZT);
        _buySellSZT = IBuySellSZT(addressBuySellSZT);
        _tokenDAI = IERC20Upgradeable(tokenDAI);
        _tokenPermitDAI = IERC20PermitUpgradeable(tokenDAI);
    }

    /// @dev one-time function aims to initialize the contract
    /// @dev MUST revert if called more than once.
    /// @param insuranceRegAddress: address of the Insurance Registry contract
    function initialize(address insuranceRegAddress) external initializer {
        _insuranceRegistry = IInsuranceRegistry(insuranceRegAddress);
        _waitingTime = 20;
        _minCoveragePoolAmount = 1e18;
        totalTokensStaked = 0;
        __BaseUpgradeablePausable_init(_msgSender());

    }

    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }

    /// @dev this function aims to update the required minimum coverage amount for underwriters' deposits
    /// @param valueInSZT: amount of SZT token
    function updateMinCoveragePoolAmount(uint256 valueInSZT) external onlyAdmin {
        _minCoveragePoolAmount = valueInSZT;
        emit UpdatedMinCoveragePoolAmount();
    }

    /// @dev this function aims to update the underwriters' withdrawal waiting delay
    /// @param timeInDays: 3-4 days will be kept as default.
    /// [PRODUCTION TODO: _waitingTime = timeInDays * 1 days;]
    function updateWaitingPeriodTime(uint256 timeInDays) external onlyAdmin {
        _waitingTime = timeInDays * 1 seconds;
        emit UpdatedWaitingPeriod(timeInDays);
    }

    /// @dev this function aims to add the coverage offered by the underwriters'
    /// @param amountInSZT: amount of SZT token
    /// @param categoryID: insurance category, e.g., stablecoin depeg insurance.
    /// @param subCategoryID: insurance sub-category, e.g., USDC depeg coverage, DAI depeg coverage.
    /// [NOTE: before calling this function, ensures SZT token has been approved.]
    function underwrite(
        uint256 amountInSZT, 
        uint256 categoryID, 
        uint256 subCategoryID,
        uint deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) public override nonReentrant returns(bool) {
        if (amountInSZT < _minCoveragePoolAmount) {
            revert CoveragePool__NotAMinimumPoolAmountError();
        }
        uint256 _tokenCounter = _buySellSZT.getTokenCounter();
        (/*uint256 amountPerToken*/, uint256 amountPaidInDAI) = _buySellSZT.calculatePriceSZT(
            _tokenCounter, (_tokenCounter + amountInSZT)
        );
        if (_tokenDAI.balanceOf(_msgSender()) < amountPaidInDAI) {
            revert CoveragePool__LowAmountError();
        }
        uint256 currVersion = _insuranceRegistry.getVersionID(categoryID) + 1;
        underwritersBalance[_msgSender()][categoryID][subCategoryID][currVersion].depositedAmount += amountInSZT;
        totalTokensStaked += amountInSZT;
        UserInfo storage userInfo = usersInfo[_msgSender()][categoryID][subCategoryID];
        if (!userInfo.isActiveInvested) {
            userInfo.startVersionBlock = currVersion;
            userInfo.isActiveInvested = true;
        }
        userPoolBalanceSZT[_msgSender()] += amountInSZT;
        _insuranceRegistry.addInsuranceLiquidity(categoryID, subCategoryID, amountPaidInDAI);
        _tokenPermitDAI.safePermit(_msgSender(), address(this), amountPaidInDAI, deadline, v, r, s);
        _tokenDAI.safeTransferFrom(_msgSender(), address(_buySellSZT), amountPaidInDAI);
        bool buySuccess = _buySellSZT.buySZTToken(_msgSender(), amountInSZT);
        if (!buySuccess) {
            revert CoveragePool__TransactionFailedError();
        }
        emit UnderwritePool(_msgSender(), categoryID, subCategoryID, amountInSZT);
        return true;
    }
    
    /// @dev this function aims to activate the SZT token withdrawal timer
    ///
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
            waitingTimeCountdown.canWithdrawTime = _waitingTime + block.timestamp;
            return true;
        }
        return false;
    }
    
    /// @dev this function aims to reduce the coverage offered by the underwriters'
    /// @param value: amount of SZT token
    /// @param categoryID: insurance category, e.g., stablecoin depeg insurance.
    /// @param subCategoryID: insurance sub-category, e.g., USDC depeg coverage, DAI depeg coverage.
    function withdraw(
        uint256 value, 
        uint256 categoryID, 
        uint256 subCategoryID,
        uint256 deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external override nonReentrant returns(bool) {
        uint256 userBalance = _insuranceRegistry.calculateUnderwriterBalance(categoryID, subCategoryID);
        WithdrawWaitPeriod storage waitTime = checkWaitTime[_msgSender()][categoryID][subCategoryID];
        if (
            (userBalance < value) || 
            (block.timestamp < waitTime.canWithdrawTime) || 
            (value > waitTime.tokenCountSZT)
        ) {
            revert CoveragePool__TransactionFailedError();
        }
        uint256 currVersion = _insuranceRegistry.getVersionID(categoryID) + 1;
        underwritersBalance[_msgSender()][categoryID][subCategoryID][currVersion].withdrawnAmount += value;
        waitTime.tokenCountSZT -= value;
        if (waitTime.tokenCountSZT == value) {
            waitTime.ifTimerStarted = false;
        }
        totalTokensStaked -= value;
        userPoolBalanceSZT[_msgSender()] -= value;
        bool removeSuccess = _insuranceRegistry.removeInsuranceLiquidity(subCategoryID, subCategoryID, value);
        bool sellSuccess = _buySellSZT.sellSZTToken(_msgSender(), value, deadline, v, r, s);
        _tokenSZT.safeTransfer(address(_buySellSZT), value);
        if (!removeSuccess || !sellSuccess) {
            revert CoveragePool__TransactionFailedError();
        }
        emit PoolWithdrawn(_msgSender(), subCategoryID, subCategoryID, value);
        return true;
    }

    function getUnderwriterActiveVersionID(
        uint256 categoryID, 
        uint256 subCategoryID
    ) external view override returns(uint256[] memory) {
        uint256 activeCount = 0;
        uint256 userStartVersion = usersInfo[_msgSender()][categoryID][subCategoryID].startVersionBlock;
        uint256 currVersion =  _insuranceRegistry.getVersionID(categoryID);
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

    function getUnderwriteSZTBalance(address userAddress) external view override returns(uint256) {
        /// it doesn't take in factor how many tokens underwriter might have diluted if hack happened
        return (userPoolBalanceSZT[userAddress] > 0 ? userPoolBalanceSZT[userAddress] : 0);
    }

    function getUnderWriterDepositedBalance(
        uint256 categoryID, 
        uint256 subCategoryID, 
        uint256 version
    ) external view override returns(uint256) {
        return underwritersBalance[_msgSender()][categoryID][subCategoryID][version].depositedAmount;
    }

    function getUnderWriterWithdrawnBalance(
        uint256 categoryID, 
        uint256 subCategoryID, 
        uint256 version
    ) external view override returns(uint256) {
        return underwritersBalance[_msgSender()][categoryID][subCategoryID][version].withdrawnAmount;
    }

    function getunderwriterCoveragePoolAmount(
        
    ) external {

    }
}