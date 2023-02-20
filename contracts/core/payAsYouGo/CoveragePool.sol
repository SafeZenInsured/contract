// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/// @title Insurance Coverage Pool Contract
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
/// [PRODUCTION TODO: waitingTime = 20;]
contract CoveragePool is ICoveragePool, BaseUpgradeablePausable {
    
    // ::::::::::::::::: STATE VARIABLES AND DECLARATIONS :::::::::::::::: //

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeERC20Upgradeable for IERC20PermitUpgradeable;

    /// tokenID: unique token ID for acceptable token addresses
    /// waitingTime: staked token withdrawal waiting time
    /// minPoolAmount: minimum coverage pool amount to be deposited in SZT ERC20 token
    /// totalTokensStaked: total amount of SZT tokens staked to underwrite insurance
    /// PLATFORM_COST: platform fee on the profit earned
    uint256 public tokenID;
    uint256 public waitingTime;
    uint256 public minPoolAmount;
    uint256 public override totalTokensStaked;
    uint256 public constant PLATFORM_COST = 90;
    
    /// buySellSZT: Buy Sell SZT contract interface
    /// tokenSZT: SZT ERC20 token interface
    /// insuranceRegistry: Insurance Registry contract interface
    IBuySellSZT public immutable buySellSZT;
    IERC20Upgradeable public immutable tokenSZT;
    IInsuranceRegistry public immutable insuranceRegistry;

    /// @notice collects underwriters' withdrawal request data
    /// ifTimerStarted: checks if the withdrawal waiting timer been activated by underwriter or not 
    /// tokenCountSZT: amount of SZT token requested for withdrawal
    /// withdrawTime: time after which the user can withdraw the requested amount of SZT token
    struct WithdrawWaitPeriod{
        bool ifTimerStarted;
        uint256 tokenCountSZT;
        uint256 withdrawTime;
    }

    /// @notice collects underwriters' global coverage offered info
    /// isActiveInvested: checks if the underwriter has
    /// depositedAmount: amount deposited (in SZT) in a particular subcategory
    /// startVersionBlock: stores underwriters' first version block number
    struct UserInfo {
        bool isActiveInvested;
        uint256 startVersionBlock;
        uint256 previousUserEpoch;
    }

    /// @notice mapping: uint256 tokenID => address tokenAddress
    mapping(uint256 => address) public override permissionedTokens;
    
    /// @dev mapping to store underwriters' global coverage offered portfolio
    /// @notice mapping: address userAddress => uint256 userPoolBalanceSZT
    mapping (address => uint256) public override userPoolBalanceSZT;

    /// @dev record the user info, i.e. if the user has invested in a particular insurance subcategory
    /// @notice mapping: user address => uint256 categoryID => uint256 subCategoryID => struct UserInfo
    mapping(address => mapping(uint256 => mapping(uint256 => UserInfo))) public usersInfo;

    // @notice mapping: address addressUser => uint256 categoryID => uint256 subCategoryID => uint256 withdrawalWaitPeriod
    mapping(address => mapping(uint256 => mapping(uint256 => WithdrawWaitPeriod))) public checkWaitTime;

    // @notice mapping: address addressUser => uint256 categoryID => uint256 subCategoryID => uint256 version => struct BalanceInfo
    mapping(address => mapping(uint256 => mapping(uint256 => mapping(uint256 => uint256)))) public override underwritersBalance;

    // ::::::::::::::::::::::::::: CONSTRUCTOR ::::::::::::::::::::::::::: //

    /// @param insuranceRegAddress: address of the Insurance Registry contract
    constructor(address addressSZT, address addressBuySellSZT, address insuranceRegAddress) {
        tokenSZT = IERC20Upgradeable(addressSZT);
        buySellSZT = IBuySellSZT(addressBuySellSZT);
        insuranceRegistry = IInsuranceRegistry(insuranceRegAddress);
    }

    // :::::::::::::::::::::::: WRITING FUNCTIONS :::::::::::::::::::::::: //

    // ::::::::::::::::::::::::: ADMIN FUNCTIONS ::::::::::::::::::::::::: //

    /// @notice initialize function, called during the contract initialization
    function initialize(address addressDAI) external initializer {
        waitingTime = 20;
        minPoolAmount = 1e18;
        permissionedTokens[tokenID] = addressDAI;
        __BaseUpgradeablePausable_init(_msgSender());

    }

    /// @notice this function aims to update the required minimum coverage amount for underwriters' deposits
    /// @param valueInSZT: amount of SZT token
    function updateMinCoveragePoolAmount(uint256 valueInSZT) external onlyAdmin {
        minPoolAmount = valueInSZT;
        emit UpdatedMinCoveragePoolAmount(valueInSZT);
    }

    /// @notice this function aims to update the underwriters' withdrawal waiting delay
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

    // :::::::::::::::::::::::: EXTERNAL FUNCTIONS ::::::::::::::::::::::: //

    /// @notice this function aims to add the coverage offered by the underwriters'
    /// @param amountInSZT: amount of SZT token
    /// @param categoryID: insurance category, e.g., stablecoin depeg insurance.
    /// @param subCategoryID: insurance sub-category, e.g., USDC depeg coverage, DAI depeg coverage.
    /// @param deadline: DAI ERC20 token permit deadline
    /// @param permitV: DAI ERC20 token permit signature (value v)
    /// @param permitR: DAI ERC20 token permit signature (value r)
    /// @param permitS: DAI ERC20 token permit signature (value s)
    function underwrite(
        uint256 tokenID_,
        uint256 amountInSZT, 
        uint256 categoryID, 
        uint256 subCategoryID,
        uint deadline, 
        uint8 permitV, 
        bytes32 permitR, 
        bytes32 permitS
    ) public override nonReentrant returns(bool) {
        if (amountInSZT < minPoolAmount) {
            revert CoveragePool__LessThanMinimumAmountError();
        }
        address tokenAddress = permissionedTokens[tokenID_];
        if(tokenAddress == address(0)) {
            revert CoveragePool__ZeroAddressInputError();
        }
        IERC20Upgradeable token = IERC20Upgradeable(tokenAddress);
        IERC20PermitUpgradeable tokenWithPermit = IERC20PermitUpgradeable(tokenAddress);
        uint256 tokenCounter = buySellSZT.tokenCounter();
        (/*uint256 amountPerToken*/, uint256 amountPaidInDAI) = buySellSZT.calculatePriceSZT(
            tokenCounter, (tokenCounter + amountInSZT)
        );
        if (token.balanceOf(_msgSender()) < amountPaidInDAI) {
            revert CoveragePool__InsufficientBalanceError();
        }

        /// insuranceRegistry.addInsuranceLiquidity() will be called later, \
        /// \ and the version will be current version + 1
        bool success = _underwrite(amountPaidInDAI, amountInSZT, categoryID, subCategoryID);
        if(!success) {
            revert CoveragePool__InternalUnderwriteOperationFailed();
        }
        tokenWithPermit.safePermit(_msgSender(), address(this), amountPaidInDAI, deadline, permitV, permitR, permitS);
        token.safeTransferFrom(_msgSender(), address(buySellSZT), amountPaidInDAI);
        bool buySuccess = buySellSZT.buyTokenSZT(_msgSender(), amountInSZT);
        if (!buySuccess) {
            revert CoveragePool__SZT_BuyOperationFailed();
        }
        emit UnderwritePool(_msgSender(), categoryID, subCategoryID, amountInSZT);
        return true;
    }

    function _underwrite(
        uint256 amountPaidInDAI,
        uint256 amountInSZT, 
        uint256 categoryID, 
        uint256 subCategoryID
    ) private returns(bool) {
        uint256 currVersion = insuranceRegistry.getVersionID(categoryID) + 1;
        
        totalTokensStaked += amountInSZT;
        UserInfo storage userInfo = usersInfo[_msgSender()][categoryID][subCategoryID];
        if (!userInfo.isActiveInvested) {
            userInfo.startVersionBlock = currVersion;
            userInfo.isActiveInvested = true;
            userInfo.previousUserEpoch = currVersion;
        }

        uint256 userPreviousEpoch = usersInfo[_msgSender()][categoryID][subCategoryID].previousUserEpoch;
        underwritersBalance[_msgSender()][categoryID][subCategoryID][currVersion] = (
            underwritersBalance[_msgSender()][categoryID][subCategoryID][userPreviousEpoch] + amountInSZT
        );

        userPoolBalanceSZT[_msgSender()] += amountInSZT;
        usersInfo[_msgSender()][categoryID][subCategoryID].previousUserEpoch = currVersion;
        bool addLiquiditySuccess = insuranceRegistry.addInsuranceLiquidity(categoryID, subCategoryID, amountPaidInDAI);
        if(!addLiquiditySuccess) {
            revert CoveragePool_AddInsuranceLiquidityOperationFailed();
        }
        return true;
    }
    
    /// @notice this function aims to activate the SZT token withdrawal timer
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
            waitingTimeCountdown.withdrawTime = waitingTime + block.timestamp;
            return true;
        }
        return false;
    }
    
    /// @notice this function aims to reduce the coverage offered by the underwriters'
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
        
        bool success = _withdraw(value, userBalance, categoryID, subCategoryID);
        if(!success) {
            revert CoveragePool__InternalWithdrawOperationFailed();
        }
        bool sellSuccess = buySellSZT.sellTokenSZT(_msgSender(), value, tokenID_, deadline, permitV, permitR, permitS);
        if(!sellSuccess) {
            revert CoveragePool__SZT_SellOperationFailed();
        }
        tokenSZT.safeTransfer(address(buySellSZT), value);
        emit PoolWithdrawn(_msgSender(), subCategoryID, subCategoryID, value);
        return true;
    }

    function _withdraw(
        uint256 value, 
        uint256 userBalance,
        uint256 categoryID, 
        uint256 subCategoryID
    ) private returns(bool) {
        WithdrawWaitPeriod storage waitTime = checkWaitTime[_msgSender()][categoryID][subCategoryID];
        if (
            (userBalance < value) || 
            (block.timestamp < waitTime.withdrawTime) || 
            (value > waitTime.tokenCountSZT)
        ) {
            revert CoveragePool__WithdrawalRestrictedError();
        }
        waitTime.tokenCountSZT -= value;
        if (waitTime.tokenCountSZT == value) {
            waitTime.ifTimerStarted = false;
        }
        uint256 currVersion = insuranceRegistry.getVersionID(categoryID) + 1;
        uint256 userPreviousEpoch = usersInfo[_msgSender()][categoryID][subCategoryID].previousUserEpoch;
        underwritersBalance[_msgSender()][categoryID][subCategoryID][currVersion] = (
            underwritersBalance[_msgSender()][categoryID][subCategoryID][userPreviousEpoch] - value
        );

        totalTokensStaked -= value;
        userPoolBalanceSZT[_msgSender()] -= value;
        usersInfo[_msgSender()][categoryID][subCategoryID].previousUserEpoch = currVersion;
        bool removeSuccess = insuranceRegistry.removeInsuranceLiquidity(subCategoryID, subCategoryID, value);
        if(!removeSuccess) {
            revert CoveragePool_RemoveInsuranceLiquidityOperationFailed();
        }
        return true;
    }

    // :::::::::::::::::::::::: READING FUNCTIONS :::::::::::::::::::::::: //
    
    // ::::::::::::::::::: PUBLIC PURE/VIEW FUNCTIONS :::::::::::::::::::: //
    
    /// this function returns the versions aka epoch when user performed deposit or withdrawal txn
    /// categoryID: insurance category, e.g., stablecoin depeg insurance.
    /// subCategoryID: insurance sub-category, e.g., USDC depeg coverage, DAI depeg coverage.
    // function getUnderwriterActiveVersionID(
    //     uint256 categoryID, 
    //     uint256 subCategoryID
    // ) public view returns(uint256[] memory) {
    //     uint256 activeCount = 0;
    //     uint256 userStartVersion = usersInfo[_msgSender()][categoryID][subCategoryID].startVersionBlock;
    //     uint256 currVersion =  insuranceRegistry.getVersionID(categoryID);
    //     for(uint256 i = userStartVersion; i <= currVersion;) {
    //         if (underwritersBalance[_msgSender()][categoryID][subCategoryID][i].depositedAmount > 0) {
    //             ++activeCount;
    //         }
    //         if (underwritersBalance[_msgSender()][categoryID][subCategoryID][i].withdrawnAmount > 0) {
    //             ++activeCount;
    //         }
    //         ++i;
    //     }
    //     uint256[] memory activeVersionID = new uint256[](activeCount);
    //     uint256 counter = 0;
    //     for(uint i = userStartVersion; i <= currVersion;) {
    //         BalanceInfo storage underwriterBalanceInfo = underwritersBalance[_msgSender()][categoryID][subCategoryID][i];
    //         if (underwriterBalanceInfo.depositedAmount > 0) {
    //             activeVersionID[counter] = i;
    //         }
    //         if (underwriterBalanceInfo.withdrawnAmount > 0) {
    //             activeVersionID[counter] = i;
    //         }
    //         ++counter;
    //         ++i;
    //     }
    //     return activeVersionID;
    // }

    // function calculateUnderwriterBalance(
    //     uint256 categoryID_,
    //     uint256 subCategoryID_
    // ) public view returns(uint256) {
    //     uint256 userBalance = 0;
    //     uint256 liquidatedAmount = 0;
    //     uint256 riskPoolCategory = 0;
    //     uint256 userPremiumEarned = 0;
    //     uint256 premiumEarnedFlowRate = 0;
    //     uint256 startVersionID = usersInfo[_msgSender()][categoryID_][subCategoryID_].startVersionBlock;        

    //     uint256 currVersion = insuranceRegistry.epoch(categoryID_);
    //     for(uint256 i = startVersionID; i <= currVersion;) {
    //         /// this check ensures that for versions when this value is not present, the user balance will be previous epoch balance
    //         /// when user last interacted with the protocol
    //         userBalance = (
    //             underwritersBalance[_msgSender()][categoryID_][subCategoryID_][i] > 0 ? 
    //             underwritersBalance[_msgSender()][categoryID_][subCategoryID_][i] : userBalance
    //         );
    //         riskPoolCategory = insuranceRegistry.epochRiskPoolCategory(categoryID_, subCategoryID_, i);
    //         (
    //             uint256 startTime, 
    //             uint256 endTime, 
    //             uint256 riskPoolLiquidity, 
    //             uint256 riskPoolStreamRate, 
    //             uint256 liquidations
    //         ) = insuranceRegistry.getVersionableRiskPoolsInfo(categoryID_, subCategoryID_, i);
    //         liquidatedAmount += (userBalance - (userBalance * liquidations) / 100);
    //         premiumEarnedFlowRate = riskPoolStreamRate;            
    //         uint256 duration = endTime - startTime;
    //         userPremiumEarned += ((duration * userBalance * premiumEarnedFlowRate * PLATFORM_COST) / (100 * riskPoolLiquidity));
    //         ++i;
    //     }
    //     userBalance -= liquidatedAmount;
    //     userBalance += userPremiumEarned;
    //     return userBalance;
    // }

    function getUserInfo(
        address addressUser,
        uint256 categoryID,
        uint256 subCategoryID
    ) external view returns(bool, uint256, uint256) {
        UserInfo memory userInfo = usersInfo[addressUser][categoryID][subCategoryID];
        return(
            userInfo.isActiveInvested,
            userInfo.startVersionBlock,
            userInfo.previousUserEpoch
        );
    }

    // ::::::::::::::::::::::::: END OF CONTRACT ::::::::::::::::::::::::: //

    // /// @notice this function returns user deposited amount for a particular epoch 
    
    // function getUnderWriterDepositedBalance(
    // ) external view {
    //     }

    // /// @notice this function returns user withdrawn amount for a particular epoch
    // function getUnderWriterWithdrawnBalance(
    // ) external view {
    // }

    // /// @notice this function returns user deposited amount for a particular subcategory insurance
    // function getUserCoveragePoolAmount(
    // ) external view {
    // }
}