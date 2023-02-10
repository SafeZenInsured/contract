// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/// @title Buy GENZ Contract
/// @author Anshik Bansal <anshik@safezen.finance>

// Importing interfaces
import "./../../interfaces/IBuyGENZ.sol";
import "./../../interfaces/IGlobalPauseOperation.sol";

/// Importing required libraries
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

// Importing contracts
import "./../../BaseUpgradeablePausable.sol";


/// Report any bug or issues at:
/// @custom:security-contact anshik@safezen.finance
contract BuyGENZ is IBuyGENZ, BaseUpgradeablePausable {

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeERC20Upgradeable for IERC20PermitUpgradeable;

    /// _saleCap: maximum GENZ ERC20 tokens to be sold in the given sale period
    /// _tokenCounter: GENZ ERC20 tokens in circulation
    /// _baseSalePrice: GENZ ERC20 token base sale price
    /// _basePriceWithDec: GENZ ERC20 token base sale price with decimals
    /// _bonusTokenPeriod: Bonus GENZ ERC20 token sale period
    /// _bonusTokenPercent: Bonus GENZ ERC20 token percentage to be rewarded
    /// _minWithdrawalPeriod: Minimum Withdrawal period to withdraw GENZ ERC20 token
    /// _commonRatio: ratio for GENZ ERC20 token price calculation
    /// WITHDRAWAL_PERIOD_MULTIPLIER: Withdrawal period multiplier to delay token withdrawal
    uint256 private _saleCap;
    uint256 private _tokenCounter;
    uint256 private _baseSalePrice;
    uint256 private _basePriceWithDec;
    uint256 private _bonusTokenPeriod;
    uint256 private _bonusTokenPercent;
    uint256 private _minWithdrawalPeriod;
    uint256 private immutable _commonRatio;
    uint256 private constant WITHDRAWAL_PERIOD_MULTIPLIER = 8 hours;

    /// _tokenDAI: DAI ERC20 token interface
    /// _tokenUSDC: USDC ERC20 token interface
    /// _globalPauseOperation: Global Pause Operations contract interface
    /// _tokenPermitDAI: DAI ERC20 token interface with permit
    IERC20Upgradeable private immutable _tokenDAI;
    IERC20Upgradeable private immutable _tokenGENZ;
    IGlobalPauseOperation private _globalPauseOperation;
    IERC20PermitUpgradeable private immutable _tokenPermitDAI;

    /// @dev collects user information related to GENZ ERC20 token purchase
    /// @param hasBought: checks whether user bought GENZ ERC20 token or not
    /// @param amount: the amount of GENZ ERC20 token user purchased
    /// @param minWithdrawTime: minmum withdrawal time to withdraw GENZ ERC20 token from the contract
    struct UserInformation {
        bool hasBought;
        uint256 amount;
        uint256 minWithdrawTime;
    }

    /// Maps:: uint256 userAddress => struct UserInformation
    mapping(address => UserInformation) private usersInformation;

    /// @dev this modifier checks if the contracts' certain function calls has to be paused temporarily
    modifier ifNotPaused() {
        require(
            (paused() != true) && 
            (_globalPauseOperation.isPaused() != true));
        _;
    }

    /// @dev initializing _tokenDAI
    /// @param value: value of the common Ratio
    /// @param decimals: decimals against the value of the commmon ratio
    /// @param tokenDAI: address of the DAI ERC20 token
    /// @param tokenGENZ: address of the GENZ ERC20 token
    /// @custom:oz-upgrades-unsafe-allow-constructor
    constructor(uint256 value, uint256 decimals, address tokenDAI, address tokenGENZ) {
        _tokenDAI = IERC20Upgradeable(tokenDAI); 
        _tokenGENZ = IERC20Upgradeable(tokenGENZ); 
        _tokenPermitDAI = IERC20PermitUpgradeable(tokenDAI);
        _commonRatio = (value * 10e17) / (10 ** decimals); // Immutable
    }

    /// @dev initialize function, called during the contract initialization
    /// @param pauseOperationAddress: address of the Global Pause Operation contract
    function initialize(
        address pauseOperationAddress
    ) external initializer {
        _baseSalePrice = 1;
        _basePriceWithDec = 1e18;
        _globalPauseOperation = IGlobalPauseOperation(pauseOperationAddress);
        __BaseUpgradeablePausable_init(_msgSender());
        emit InitializedContractBuyGENZ(_msgSender());
    }

    /// @dev this function aims to update token base sale price
    /// @param updatedTokenPrice: updated GENZ ERC20 token base sale price
    function updateBaseSalePrice(uint256 updatedTokenPrice) external onlyAdmin {
        _baseSalePrice = updatedTokenPrice;
        _basePriceWithDec = updatedTokenPrice * 1e18;
        emit UpdatedBaseSalePrice(updatedTokenPrice);
    }

    /// @dev this function aims to update the minimum withdrawal period for token withdrawal from contract
    /// @param timeInMinutes: will be kept as 15 days.
    /// [PRODUCTION TODO: _minWithdrawalPeriod = timeInDays * 1 days;]
    function updateMinimumWithdrawalPeriod(uint256 timeInMinutes) external onlyAdmin {
        _minWithdrawalPeriod = timeInMinutes * 1 minutes;
        emit UpdatedMinimumWithdrawalPeriod(timeInMinutes);
    }

    /// @dev this function aims to pause the contracts' certain functions temporarily
    function pause() external onlyAdmin {
        _pause();
    }

    /// @dev this function aims to resume the complete contract functionality
    function unpause() external onlyAdmin {
        _unpause();
    }

    /// @dev this function faciliate users' to buy GENZ ERC20 token
    /// @param value: amount of GENZ ERC20 tokens user wishes to purchase
    /// @param deadline: DAI ERC20 token permit deadline
    /// @param permitV: DAI ERC20 token permit signature (value v)
    /// @param permitR: DAI ERC20 token permit signature (value r)
    /// @param permitS: DAI ERC20 token permit signature (value s)
    function buyGENZToken(
        uint256 value,
        uint256 deadline, 
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS
    ) external override nonReentrant ifNotPaused returns(bool) {
        if (value < 1e18) {
            revert BuySellGENZ__LowAmountError();
        }
        _minWithdrawalPeriod += WITHDRAWAL_PERIOD_MULTIPLIER;
        (/* uint256 amountPerToken */, uint256 amountToBePaid) = calculatePriceGENZ(
            _tokenCounter, _tokenCounter + value);
        if (amountToBePaid > _tokenDAI.balanceOf(_msgSender())) {
            revert BuySellGENZ__InsufficientBalanceError();
        }
        UserInformation storage userStakeInformation = usersInformation[_msgSender()];
        userStakeInformation.amount += value;
        userStakeInformation.hasBought = true;
        userStakeInformation.minWithdrawTime = block.timestamp + _minWithdrawalPeriod;
        _tokenPermitDAI.safePermit(_msgSender(), address(this), amountToBePaid, deadline, permitV, permitR, permitS);
        _tokenDAI.safeTransferFrom(_msgSender(), address(this), amountToBePaid);
        return true;
    }

    /// @dev this function aims to faciliate users' GENZ token withdrawal to their respcective wallets
    function withdrawTokens() external {
        if (!usersInformation[_msgSender()].hasBought) {
            revert BuyGENZ__ZeroTokensPurchasedError();
        }
        if (usersInformation[_msgSender()].minWithdrawTime > block.timestamp ) {
            revert BuyGENZ__EarlyWithdrawalRequestedError();
        }
        uint256 amountStaked = usersInformation[_msgSender()].amount;
        usersInformation[_msgSender()].hasBought = false;
        usersInformation[_msgSender()].amount = 0;
        _tokenGENZ.safeTransfer(_msgSender(), amountStaked);
    }


    // ::::::::::::::::::::::::: VIEW FUNCTIONS ::::::::::::::::::::::::: //

    /// @dev this function aims to calculate the current GENZ ERC20 token price
    /// @param issuedTokensGENZ: total number of GENZ ERC20 token issued to date
    /// @param requiredTokens: issuedTokensGENZ + amount of GENZ ERC20 user wishes to purchase
    function calculatePriceGENZ(
        uint256 issuedTokensGENZ, 
        uint256 requiredTokens
    ) public view override returns(uint256, uint256) {
        uint256 commonRatioGENZ = _commonRatio * _baseSalePrice;
        uint256 tokenDifference = (issuedTokensGENZ + (requiredTokens - 1e18));
        uint256 averageDiff = ((commonRatioGENZ * tokenDifference) / 2) / 1e18;
        uint256 amountPerToken = _basePriceWithDec + averageDiff;
        uint256 amountToBePaid = (amountPerToken * (requiredTokens - issuedTokensGENZ))/1e18;
        return (amountPerToken, amountToBePaid);
    }

    /// @dev this function aims to returns the token in circulation
    function getGENZTokenCount() public view override returns(uint256) {
        return _tokenCounter;
    }

    /// @dev this function aims to get the current GENZ ERC20 token price with decimals
    function getBasePriceWithDec() external view override returns(uint256) {
        return _basePriceWithDec;
    }

    /// @dev this function aims to get the current GENZ ERC20 token price
    function getCurrentTokenPrice() public view override returns(uint256) {
        (uint256 amountPerToken, /*uint256 amountToBePaid*/) = calculatePriceGENZ(
            _tokenCounter, _tokenCounter + 1e18);
        return amountPerToken;
    }

    // :::::::::::::::::::::::: END OF CONTRACT :::::::::::::::::::::::: //    
}