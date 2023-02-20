// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/// @title Buy Sell SZT Contract
/// @author Anshik Bansal <anshik@safezen.finance>

// Importing interfaces
import "./../../interfaces/IBuySellSZT.sol";
import "./../../interfaces/ICoveragePool.sol";
import "./../../interfaces/IERC20Extended.sol";
import "./../../interfaces/IGlobalPauseOperation.sol";

/// Importing required libraries
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

// Importing contracts
import "./../../BaseUpgradeablePausable.sol";

/// Report any bug or issues at:
/// @custom:security-contact anshik@safezen.finance
contract BuySellSZT is IBuySellSZT, BaseUpgradeablePausable {

    // :::::::::::::::::::::::: CUSTOM ERROR CODE :::::::::::::::::::::::: //
    // :::::::::::::::::::::::::: CUSTOM EVENTS :::::::::::::::::::::::::: //
    // ::::::::::::::::: STATE VARIABLES AND DECLARATIONS :::::::::::::::: //
    // ::::::::::::::::::::::::::: CONSTRUCTOR ::::::::::::::::::::::::::: //
    // ::::::::::::::::::::::::: ADMIN FUNCTIONS ::::::::::::::::::::::::: //
    // :::::::::::::::::::::::: WRITING FUNCTIONS :::::::::::::::::::::::: //
    // :::::::::::::::::::::::: EXTERNAL FUNCTIONS ::::::::::::::::::::::: //
    // :::::::::::::::::::::::: PUBLIC FUNCTIONS ::::::::::::::::::::::::: //
    // ::::::::::::::::::::::: INTERNAL FUNCTIONS :::::::::::::::::::::::: //
    // :::::::::::::::::::::::: PRIVATE FUNCTIONS :::::::::::::::::::::::: //
    // :::::::::::::::::::::::: READING FUNCTIONS :::::::::::::::::::::::: //
    // ::::::::::::::::::: EXTERNAL PURE/VIEW FUNCTIONS :::::::::::::::::: //
    // ::::::::::::::::::: PUBLIC PURE/VIEW FUNCTIONS :::::::::::::::::::: //
    // :::::::::::::::::: INTERNAL PURE/VIEW FUNCTIONS ::::::::::::::::::: //
    // ::::::::::::::::::: PRIVATE PURE/VIEW FUNCTIONS ::::::::::::::::::: //
    // ::::::::::::::::::::::::: END OF CONTRACT ::::::::::::::::::::::::: //



    // ::::::::::::::::: STATE VARIABLES AND DECLARATIONS :::::::::::::::: //

    using SafeERC20Upgradeable for IERC20Extended;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeERC20Upgradeable for IERC20PermitUpgradeable;

    /// initCounter: counter to initialize the init one-time function, max value can be 1.
    /// tokenCounter: SZT ERC20 tokens in circulation.
    /// commonRatio: ratio for SZT ERC20 YUVAA token price calculation.
    /// SZT_BASE_PRICE: SZT ERC20 token base price.
    /// SZT_BASE_PRICE_WITH_DEC: SZT ERC20 token base price with decimals.
    uint256 public initCounter;
    uint256 public override tokenCounter;
    uint256 public immutable commonRatio;
    uint256 public constant SZT_BASE_PRICE = 100;
    uint256 public constant SZT_BASE_PRICE_WITH_DEC = 100 * 1e18;

    /// tokenGSZT: GSZT ERC20 token interface
    /// tokenSZT: SZT ERC20 token interface
    /// tokenPermitGSZT: GSZT ERC20 token interface with permit
    /// coveragePool: Coverage Pool contract interface
    /// globalPauseOperation: Pause Operation contract interface
    IERC20Extended public tokenGSZT;
    IERC20Upgradeable public tokenSZT;
    IERC20PermitUpgradeable public tokenPermitGSZT;
    ICoveragePool public coveragePool;
    IGlobalPauseOperation public globalPauseOperation;

    // ::::::::::::::::::::::::::: CONSTRUCTOR ::::::::::::::::::::::::::: //

    /// @notice initializing commonRatio
    /// @param value: value of the common Ratio
    /// @param decimals: decimals against the value of the commmon ratio
    /// @custom:oz-upgrades-unsafe-allow-constructor
    constructor(uint256 value, uint256 decimals) {
        commonRatio = (value * 1e18) / (10 ** decimals); // Immutable
    }

    // ::::::::::::::::::::::::: ADMIN FUNCTIONS ::::::::::::::::::::::::: //

    /// @notice initialize function, called during the contract initialization
    function initialize() external initializer {
        __BaseUpgradeablePausable_init(_msgSender());
        emit InitializedContractBuySellSZT(_msgSender());
    }

    /// @notice one time function to initialize the contract
    /// @param addressSZT: address of the SZT token
    /// @param addressGSZT: address of the GSZT token
    /// @param addressCoveragePool: address of the coverage pool contract
    /// @param addressGlobalPauseOperation: address of the Global Pause Operation contract
    function init(
        address addressSZT,
        address addressGSZT,
        address addressCoveragePool,
        address addressGlobalPauseOperation
    ) external onlyAdmin {
        if (initCounter > 0) {
            revert BuySellSZT__InitializedEarlierError();
        }
        ++initCounter;
        tokenSZT = IERC20Upgradeable(addressSZT);
        tokenGSZT = IERC20Extended(addressGSZT);
        tokenPermitGSZT = IERC20PermitUpgradeable(addressGSZT);
        coveragePool = ICoveragePool(addressCoveragePool);
        globalPauseOperation = IGlobalPauseOperation(addressGlobalPauseOperation);
        emit InitializedContractBuySellSZT(_msgSender());
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
    
    /// @notice this function faciliate users' to buy SZT ERC20 non-speculative token
    /// @param addressUser: user wallet address
    /// @param amountInSZT: amount of SZT tokens user wishes to purchase
    function buyTokenSZT(
        address addressUser,
        uint256 amountInSZT
    ) external override nonReentrant returns(bool) {
        ifNotPaused();
        _isPermitted();
        if ((tokenCounter < 1e18) && (amountInSZT < 1e18)) {
            revert BuySellSZT__LessThanMinimumAmountError();
        }
        tokenCounter += amountInSZT;
        tokenSZT.safeTransfer(_msgSender(), amountInSZT);
        bool mintSuccessGSZT = _mintGSZT(addressUser, amountInSZT);
        if ((!mintSuccessGSZT)) {
            revert BuySellSZT__MintFailedGSZT();
        }
        emit BoughtSZT(_msgSender(), amountInSZT);
        return true;
    }
    
    /// @notice this function faciliate users' sell SZT ERC20 token
    /// @param amountInSZT: amount of SZT tokens user wishes to sell
    /// @param deadline: GSZT ERC20 token permit deadline
    /// @param permitV: GSZT ERC20 token permit signature (value v)
    /// @param permitR: GSZT ERC20 token permit signature (value r)
    /// @param permitS: GSZT ERC20 token permit signature (value s)
    function sellTokenSZT(
        address addressUser,
        uint256 amountInSZT,
        uint256 tokenID,
        uint256 deadline, 
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS
    ) external override nonReentrant returns(bool) {
        ifNotPaused();
        _isPermitted();
        uint256 tokenCount = tokenCounter;
        (/*amountPerToken*/, uint256 amountToBeReleased) = calculatePriceSZT(
            (tokenCount - amountInSZT), tokenCount
        );
        tokenCounter -= amountInSZT;
        tokenPermitGSZT.safePermit(
            addressUser, address(this), amountInSZT, deadline, permitV, permitR, permitS
        );
        bool burnSuccessGSZT = tokenGSZT.burnFrom(
            addressUser, _burnTokenGSZT(_msgSender())
        );
        if ((!burnSuccessGSZT)) {
            revert BuySellSZT__BurnFailedGSZT();
        }
        address addressToken = coveragePool.permissionedTokens(tokenID);
        IERC20Upgradeable(addressToken).safeTransfer(addressUser, amountToBeReleased);
        emit SoldSZT(_msgSender(), amountInSZT);
        return true;
    }

    // :::::::::::::::::::::::: PRIVATE FUNCTIONS :::::::::::::::::::::::: //

    /// @notice this function aims to mint the GSZT tokens to the provided user address
    /// @param addressUser: user wallet address
    /// @param userBalanceSZT: user SZT ERC20 token balance
    function _mintGSZT(
        address addressUser,
        uint256 userBalanceSZT
    ) private returns(bool) {
        uint256 amountUnderwritten = coveragePool.userPoolBalanceSZT(addressUser);
        uint256 tokenCountGSZT = _calculateTokenCountGSZT(userBalanceSZT + amountUnderwritten);
        tokenCountGSZT = (tokenCountGSZT > (22750 * 1e18)) ? (userBalanceSZT / 2) : tokenCountGSZT;
        uint256 currentBalanceGSZT = tokenGSZT.balanceOf(addressUser);
        uint256 toMint = tokenCountGSZT - currentBalanceGSZT;
        bool success = tokenGSZT.mint(addressUser, toMint);
        if (!success) {
            revert BuySellSZT__MintFailedGSZT();
        }
        emit MintedGSZT(addressUser, toMint);
        return true;
    }

    // :::::::::::::::::::::::: READING FUNCTIONS :::::::::::::::::::::::: //
    
    // ::::::::::::::::::: EXTERNAL PURE/VIEW FUNCTIONS :::::::::::::::::: //
    
    /// @notice this function aims to get the real time price of SZT ERC20 token
    function getRealTimePriceSZT() external view override returns(uint256) {
        uint256 commonRatioSZT = (commonRatio * SZT_BASE_PRICE * tokenCounter) / 1e18;
        uint256 amountPerToken = (SZT_BASE_PRICE * (1e18)) + commonRatioSZT;
        return amountPerToken;
    }

    // ::::::::::::::::::: PUBLIC PURE/VIEW FUNCTIONS :::::::::::::::::::: //

    /// @dev this function checks if the contracts' certain function calls has to be paused temporarily
    function ifNotPaused() public view {
        if((paused()) || (globalPauseOperation.isPaused())) {
            revert BuySellSZT__OperationPaused();
        } 
    }

    /// @notice calculate the SZT token value for the asked amount of SZT tokens
    /// @param issuedTokensSZT: the amount of SZT tokens in circulation
    /// @param requiredTokens: issuedTokensSZT +  ERC20 SZT tokens user wishes to purchase
    function calculatePriceSZT(
        uint256 issuedTokensSZT, 
        uint256 requiredTokens
    ) public view override returns(uint256, uint256) {
        uint256 commonRatioSZT = commonRatio * SZT_BASE_PRICE;
        uint256 tokenDifference = (issuedTokensSZT + (requiredTokens - 1e18));
        uint256 averageDiff = ((commonRatioSZT * tokenDifference) / 2) / 1e18;
        uint256 amountPerToken = SZT_BASE_PRICE_WITH_DEC + averageDiff;
        uint256 amountToBePaid = (amountPerToken * (requiredTokens - issuedTokensSZT))/1e18;
        return (amountPerToken, amountToBePaid);
    }

    // ::::::::::::::::::: PRIVATE PURE/VIEW FUNCTIONS ::::::::::::::::::: //

    /// @notice this function restricts function calls accessible to the coverage pool contract address only.
    function _isPermitted() private view {
        if(_msgSender() != address(coveragePool)) {
            revert BuySellSZT__AccessRestricted();
        }
    }

    /// @notice this function facilitates burning of users' GSZT tokens
    /// @param addressUser: user wallet address
    function _burnTokenGSZT(address addressUser) private view returns(uint256) {
        uint256 userBalanceSZT = tokenSZT.balanceOf(addressUser);
        uint256 amountUnderwritten = coveragePool.userPoolBalanceSZT(addressUser);
        uint256 expectedBalanceGSZT = _calculateTokenCountGSZT(userBalanceSZT + amountUnderwritten);
        uint256 currentBalanceGSZT = tokenGSZT.balanceOf(addressUser);
        uint256 amountToBeBurned = currentBalanceGSZT - expectedBalanceGSZT;
        return amountToBeBurned;
    }

    /// @notice this function aims to calculate the common ratio for the GSZT token calculation
    /// @param issuedTokensSZT: amount of SZT tokens currently in circulation
    /// @param alpha: alpha value for the calculation of GSZT token
    /// @param decimals: to calculate the actual alpha value for GSZT tokens 
    function _calculateCommonRatioGSZT(
        uint256 issuedTokensSZT, 
        uint256 alpha, 
        uint256 decimals
    ) private pure returns(uint256) {
        uint256 mantissa = 10 ** decimals;
        uint256 tokenValue = (alpha * SZT_BASE_PRICE * issuedTokensSZT) / mantissa;
        uint256 amountPerToken = SZT_BASE_PRICE_WITH_DEC + tokenValue;
        return amountPerToken;
    }

    /// @notice this function aims to calculate the GSZT amount to be minted
    /// @param issuedTokensSZT: user SZT ERC20 token balance
    function _calculateTokenCountGSZT(
        uint256 issuedTokensSZT
    ) private pure returns(uint256) {
        uint256 commonRatio_17_2 = (
            (SZT_BASE_PRICE * 1e36) / 
            _calculateCommonRatioGSZT(issuedTokensSZT, 17, 2)
        );
        uint256 commonRatio_22_6 = (
            (_calculateCommonRatioGSZT(issuedTokensSZT, 22, 6) / 
            (SZT_BASE_PRICE)) - (1e18)
        );
        uint256 tokenAmountGSZT = ((commonRatio_17_2 + commonRatio_22_6) * issuedTokensSZT) / 1e18;
        return tokenAmountGSZT;
    }

    // :::::::::::::::::::::::: END OF CONTRACT :::::::::::::::::::::::: //

}