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

/// [PRODUCTION TODO: minWithdrawalPeriod = timeInDays * 1 days;]
/// [PRODUCTION TODO: minWithdrawalPeriod = 7 days;]
/// INTEGRATING UNISWAP LIQUIDITY FUNCTION & COVERAGE FUNCTION

contract BuyGENZ is IBuyGENZ, BaseUpgradeablePausable {

    
    // ::::::::::::::::: STATE VARIABLES AND DECLARATIONS :::::::::::::::: //

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeERC20Upgradeable for IERC20PermitUpgradeable;

    /// saleCap: maximum GENZ ERC20 tokens to be sold in the given sale period
    /// tokenID: unique token ID for acceptable token addresses
    /// tokenCounter: GENZ ERC20 tokens in circulation
    /// basePriceWithDec: GENZ ERC20 token base sale price with decimals
    /// bonusTokenPeriod: Bonus GENZ ERC20 token sale period
    /// bonusTokenPercent: Bonus GENZ ERC20 token percentage to be rewarded
    /// minWithdrawalPeriod: Minimum Withdrawal period to withdraw GENZ ERC20 token
    /// WITHDRAWAL_PERIOD_MULTIPLIER: Withdrawal period multiplier to delay token withdrawal
    uint256 public saleCap;
    uint256 public tokenID;
    uint256 public totalSupply;
    uint256 public tokenCounter;
    uint256 public basePriceWithDec;
    uint256 public bonusTokenPeriod;
    uint256 public bonusTokenPercent;
    uint256 public minWithdrawalPeriod;
    uint256 public constant WITHDRAWAL_PERIOD_MULTIPLIER = 8 hours;

    /// tokenGENZ: GENZ ERC20 token interface
    /// globalPauseOperation: Global Pause Operations contract interface
    IERC20Upgradeable public immutable tokenGENZ;
    IGlobalPauseOperation public globalPauseOperation;

    /// @notice mapping: uint256 tokenID => address tokenAddress
    mapping(uint256 => address) public permissionedTokens;

    /// @dev collects user information related to GENZ ERC20 token purchase
    /// @param hasBought: checks whether user bought GENZ ERC20 token or not
    /// @param amount: the amount of GENZ ERC20 token user purchased
    /// @param minWithdrawTime: minmum withdrawal time to withdraw GENZ ERC20 token from the contract
    struct UserInformation {
        bool hasBought;
        uint256 amount;
        uint256 minWithdrawTime;
    }

    /// @notice Maps:: addressUser(address) => UserInformation(struct)
    mapping(address => UserInformation) public usersInformation;

    // ::::::::::::::::::::::::::: CONSTRUCTOR ::::::::::::::::::::::::::: //

    /// @dev initializing ERC20 GENZ token
    /// @param addressGENZ: GENZ ERC20 token address
    /// @custom:oz-upgrades-unsafe-allow-constructor
    constructor(address addressGENZ) {
        tokenGENZ = IERC20Upgradeable(addressGENZ);
    }

    // ::::::::::::::::::::::::: ADMIN FUNCTIONS ::::::::::::::::::::::::: //

    /// @dev initialize function, called during the contract initialization
    /// @param addressDAI: DAI ERC20 token address
    /// @param addressGlobalPauseOperation: Global Pause Operation contract address
    function initialize(
        address addressDAI,
        address addressGlobalPauseOperation
    ) external initializer {
        ++tokenID;
        saleCap = 1e25;
        totalSupply = 1e26;
        basePriceWithDec = 1e17;
        bonusTokenPeriod = block.timestamp + 2 days;
        bonusTokenPercent = 1;
        minWithdrawalPeriod = 10 minutes;
        permissionedTokens[tokenID] = addressDAI;
        globalPauseOperation = IGlobalPauseOperation(addressGlobalPauseOperation);
        __BaseUpgradeablePausable_init(_msgSender());
        emit InitializedContractBuyGENZ(_msgSender());
    }

    /// @notice this function facilitates withdrawal of funds for project operations
    /// @param to: destination address
    /// @param tokenID_: unique token ID
    /// @param amount: amount to be transferred
    function transferFunds(
        address to,
        uint256 tokenID_,
        uint256 amount
    ) external onlyAdmin {
        address tokenAddress = permissionedTokens[tokenID_];
        if(tokenAddress == address(0)) {
            revert BuyGENZ__ZeroAddressInputError();
        }
        IERC20Upgradeable token = IERC20Upgradeable(tokenAddress);
        token.safeIncreaseAllowance(to, amount);
        token.safeTransfer(to, amount);
        emit FundsTransferred(to, amount);
    }

    /// @dev this function aims to update token base sale price
    /// @param updatedTokenPrice: updated GENZ ERC20 token base sale price
    function updateBaseSalePrice(uint256 updatedTokenPrice) external onlyAdmin {
        basePriceWithDec = updatedTokenPrice;
        emit UpdatedBaseSalePrice(updatedTokenPrice);
    }

    /// @dev this function aims to update the minimum withdrawal period for token withdrawal from contract
    /// @param timeInMinutes: will be kept as 15 days.
    /// [PRODUCTION TODO: minWithdrawalPeriod = timeInDays * 1 days;]
    function updateMinimumWithdrawalPeriod(uint256 timeInMinutes) external onlyAdmin {
        minWithdrawalPeriod = timeInMinutes * 1 minutes;
        emit UpdatedMinimumWithdrawalPeriod(timeInMinutes);
    }

    /// @notice this function aims to update the sale cap
    function updateSaleCap(uint256 updatedSaleCap) external onlyAdmin {
        saleCap = updatedSaleCap;
        emit UpdatedSaleCap(updatedSaleCap);
    }

    /// @notice this function facilitates adding new supported payment tokens for GENZ ERC20 token purchase
    function addTokenAddress(address addressToken) external onlyAdmin {
        if(addressToken == address(0)) {
            revert BuyGENZ__ZeroAddressInputError();
        }
        ++tokenID;
        permissionedTokens[tokenID] = addressToken;
        emit NewTokenAdded(tokenID, addressToken);
    }

    /// @notice this function aims to update the bonus token period
    function updateBonusTokenPeriod(uint256 timeInHours) external onlyAdmin {
        bonusTokenPeriod = (timeInHours * 1 hours) + block.timestamp;
        emit UpdatedBonusTokenPeriod(timeInHours);
    }

    /// @notice this function aims to update the bonus token percent, to be given during the bonus period.
    function updateBonusTokenPercent(uint256 updatedPercent) external onlyAdmin {
        bonusTokenPercent = updatedPercent;
        emit UpdatedBonusTokenPercent(updatedPercent);
    }

    /// @dev this function aims to pause the contracts' certain functions temporarily
    function pause() external onlyAdmin {
        _pause();
    }

    /// @dev this function aims to resume the complete contract functionality
    function unpause() external onlyAdmin {
        _unpause();
    }

    // :::::::::::::::::::::::: WRITING FUNCTIONS :::::::::::::::::::::::: //
    
    // :::::::::::::::::::::::: EXTERNAL FUNCTIONS ::::::::::::::::::::::: //
    
    /// @dev this function faciliate users' to buy GENZ ERC20 token
    /// @param tokenID_: unique token ID for acceptable token address
    /// @param amountInGENZ: amount of GENZ ERC20 tokens user wishes to purchase
    /// @param deadline: ERC20 token permit deadline
    /// @param permitV: ERC20 token permit signature (value v)
    /// @param permitR: ERC20 token permit signature (value r)
    /// @param permitS: ERC20 token permit signature (value s)
    function buyGENZToken(
        uint256 tokenID_,
        uint256 amountInGENZ,
        uint256 deadline, 
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS
    ) external override nonReentrant returns(bool) {
        ifNotPaused();
        if (amountInGENZ < 1e21) {
            revert BuyGENZ__LessThanMinimumAmountError();
        }
        address tokenAddress = permissionedTokens[tokenID_];
        if(tokenAddress == address(0)) {
            revert BuyGENZ__ZeroAddressInputError();
        }
        IERC20Upgradeable token = IERC20Upgradeable(tokenAddress);
        IERC20PermitUpgradeable tokenWithPermit = IERC20PermitUpgradeable(tokenAddress);
        uint256 amountToBePaid = basePriceWithDec * amountInGENZ;
        if (amountToBePaid > token.balanceOf(_msgSender())) {
            revert BuySellGENZ__InsufficientBalanceError();
        }
        if (block.timestamp < bonusTokenPeriod) {
            // bonusTokens = (bonusTokenPercent * totalSupply) / 100 ;
            // userShare = (amountInGENZ / saleCap) * 100;
            amountInGENZ += (amountInGENZ * bonusTokenPercent * totalSupply / saleCap);
        }
        tokenCounter += amountInGENZ;
        minWithdrawalPeriod += WITHDRAWAL_PERIOD_MULTIPLIER;
        UserInformation storage userInformation = usersInformation[_msgSender()];
        userInformation.hasBought = true;
        userInformation.amount += amountInGENZ;
        userInformation.minWithdrawTime = block.timestamp + minWithdrawalPeriod;
        tokenWithPermit.safePermit(_msgSender(), address(this), amountToBePaid, deadline, permitV, permitR, permitS);
        token.safeTransferFrom(_msgSender(), address(this), amountToBePaid);
        emit BoughtGENZ(_msgSender(), amountInGENZ);
        return true;
    }

    /// @dev this function aims to faciliate users' GENZ token withdrawal to their respcective wallets
    function withdrawTokens() external override nonReentrant returns(bool) {
        ifNotPaused();
        if (!usersInformation[_msgSender()].hasBought) {
            revert BuyGENZ__ZeroTokensPurchasedError();
        }
        if (usersInformation[_msgSender()].minWithdrawTime > block.timestamp ) {
            revert BuyGENZ__EarlyWithdrawalRequestedError();
        }
        uint256 amountStaked = usersInformation[_msgSender()].amount;
        usersInformation[_msgSender()].hasBought = false;
        usersInformation[_msgSender()].amount = 0;
        tokenGENZ.safeTransfer(_msgSender(), amountStaked);
        emit WithdrawnGENZ(_msgSender(), amountStaked);
        return true;
    }

    // :::::::::::::::::::::::: READING FUNCTIONS :::::::::::::::::::::::: //
    
    // ::::::::::::::::::: PUBLIC PURE/VIEW FUNCTIONS :::::::::::::::::::: //

    /// @dev this function checks if the contracts' certain function calls has to be paused temporarily
    function ifNotPaused() public view {
        if((paused()) || (globalPauseOperation.isPaused())) {
            revert BuyGENZ__OperationPaused();
        } 
    }

    // :::::::::::::::::::::::: END OF CONTRACT :::::::::::::::::::::::: //    
}