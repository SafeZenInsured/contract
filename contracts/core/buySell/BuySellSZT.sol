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
    /// _initVersion: counter to initialize the init one-time function, max value can be 1.
    /// _tokenCounter: SZT ERC20 tokens in circulation
    /// _commonRatio: ratio for SZT ERC20 YUVAA token price calculation
    /// SZT_BASE_PRICE: SZT ERC20 token base price
    /// SZT_BASE_PRICE_WITH_DEC: SZT ERC20 token base price with decimals
    uint256 private _initVersion;
    uint256 private _tokenCounter;
    uint256 private immutable _commonRatio;
    uint256 private constant SZT_BASE_PRICE = 100;
    uint256 private constant SZT_BASE_PRICE_WITH_DEC = 100 * 1e18;

    using SafeERC20Upgradeable for IERC20Extended;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeERC20Upgradeable for IERC20PermitUpgradeable;

    /// _tokenGSZT: GSZT ERC20 token interface
    /// _tokenSZT: SZT ERC20 token interface
    /// _tokenDAI: DAI ERC20 token interface
    /// _tokenPermitGSZT: GSZT ERC20 token interface with permit
    /// _tokenPermitDAI: DAI ERC20 token interface with permit
    /// _coveragePool: Coverage Pool contract interface
    /// _globalPauseOperation: Pause Operation contract interface
    IERC20Extended private _tokenGSZT;
    IERC20Upgradeable private _tokenSZT;
    IERC20Upgradeable private immutable _tokenDAI;
    IERC20PermitUpgradeable private _tokenPermitGSZT;
    IERC20PermitUpgradeable private immutable _tokenPermitDAI;
    ICoveragePool private _coveragePool;
    IGlobalPauseOperation private _globalPauseOperation;
    
    /// @notice immutable commonRatio, initializing _tokenDAI and _tokenDAIPermit interfaces
    /// @param value: value of the common Ratio
    /// @param decimals: decimals against the value of the commmon ratio
    /// @param tokenDAI: address of the DAI token
    /// @custom:oz-upgrades-unsafe-allow-constructor
    constructor(uint256 value, uint256 decimals, address tokenDAI) {
        _tokenDAI = IERC20Upgradeable(tokenDAI); // Immutable
        _tokenPermitDAI = IERC20PermitUpgradeable(tokenDAI); //Immutable
        _commonRatio = (value * 10e17) / (10 ** decimals); // Immutable
    }

    /// @notice function access restricted to the coverage pool contract address calls only
    modifier isPermitted() {
        require(_msgSender() == address(_coveragePool));
        _;
    }

    /// @notice this modifier checks if the contracts' certain function calls has to be paused temporarily
    modifier ifNotPaused() {
        require(
            (paused() != true) && 
            (_globalPauseOperation.isPaused() != true));
        _;
    }

    /// @notice initialize function, called during the contract initialization
    function initialize() external initializer {
        __BaseUpgradeablePausable_init(_msgSender());
    }

    /// @notice one time function to initialize the contract
    /// @param safeZenTokenAddress: address of the SZT token
    /// @param coveragePoolAddress: address of the coverage pool contract
    /// @param safezenGovernanceTokenCA: address of the GSZT token
    /// @param pauseOperationAddress: address of the Global Pause Operation contract
    function init(
        address safeZenTokenAddress,
        address coveragePoolAddress,
        address safezenGovernanceTokenCA,
        address pauseOperationAddress
    ) external onlyAdmin {
        if (_initVersion > 0) {
            revert BuySellSZT__ImmutableChangesError();
        }
        ++_initVersion;
        _tokenSZT = IERC20Upgradeable(safeZenTokenAddress);
        _tokenPermitGSZT = IERC20PermitUpgradeable(safezenGovernanceTokenCA);
        _coveragePool = ICoveragePool(coveragePoolAddress);
        _tokenGSZT = IERC20Extended(safezenGovernanceTokenCA);
        _globalPauseOperation = IGlobalPauseOperation(pauseOperationAddress);
    }

    /// @notice to pause the certain functions within the contract
    function pause() external onlyAdmin {
        _pause();
    }

    /// @notice to unpause the certain functions paused earlier within the contract
    function unpause() external onlyAdmin {
        _unpause();
    }

    /// @notice buying our native non-speculative SZT token
    /// @param userAddress: user wallet address
    /// @param amountInSZT: amount of SZT tokens user wishes to purchase
    function buySZTToken(
        address userAddress,
        uint256 amountInSZT
    ) external ifNotPaused nonReentrant returns(bool) {
        if ((_tokenCounter < 1e18) && (amountInSZT < 1e18)) {
            revert BuySellSZT__LowAmountError();
        }
        _tokenCounter += amountInSZT;
        _tokenSZT.safeTransfer(_msgSender(), amountInSZT);
        bool mintSuccessGSZT = _mintGSZT(userAddress, amountInSZT);
        if ((!mintSuccessGSZT)) {
            revert BuySellSZT__TransactionFailedError();
        }
        emit BoughtSZT(_msgSender(), amountInSZT);
        return true;
    }
    
    /// NOTE: approve SZT and GSZT amount to BuySellContract before calling this function
    /// @notice selling the SZT tokens
    /// @param value: the amounnt of SZT tokens user wishes to sell
    /// @param deadline: GSZT ERC20 token permit deadline
    /// @param permitV: GSZT ERC20 token permit signature (value v)
    /// @param permitR: GSZT ERC20 token permit signature (value r)
    /// @param permitS: GSZT ERC20 token permit signature (value s)
    function sellSZTToken(
        address userAddress,
        uint256 value,
        uint256 deadline, 
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS
    ) external ifNotPaused nonReentrant returns(bool) {
        uint256 tokenCount = getTokenCounter();
        (/*amountPerToken*/, uint256 amountToBeReleased) = calculatePriceSZT(
            (tokenCount - value), tokenCount
        );
        _tokenCounter -= value;
        _tokenPermitGSZT.safePermit(
            userAddress, address(this), value, deadline, permitV, permitR, permitS
        );
        bool burnSuccessGSZT = _tokenGSZT.burnFrom(
            userAddress, _burnTokenGSZT(_msgSender())
        );
        _tokenDAI.safeTransfer(userAddress, amountToBeReleased);
        if ((!burnSuccessGSZT)) {
            revert BuySellSZT_sellSZTToken__TxnFailedError();
        }
        emit SoldSZT(_msgSender(), value);
        return true;
    }

    /// @notice minting the GSZT tokens to the provided user address
    /// @param userAddress: user wallet address
    /// @param userBalanceSZT: user SZT ERC20 token balance
    function _mintGSZT(
        address userAddress,
        uint256 userBalanceSZT
    ) private returns(bool) {
        uint256 amountUnderwritten = _coveragePool.getUnderwriteSZTBalance(userAddress);
        uint256 tokenCountGSZT = _calculateTokenCountGSZT(userBalanceSZT + amountUnderwritten);
        tokenCountGSZT = (tokenCountGSZT > (22750 * 1e18)) ? (userBalanceSZT / 2) : tokenCountGSZT;
        uint256 userBalanceGSZT = _tokenGSZT.balanceOf(userAddress);
        uint256 toMint = tokenCountGSZT - userBalanceGSZT;
        bool success = _tokenGSZT.mint(userAddress, toMint);
        if (!success) {
            revert BuySellSZT_mintGSZT__MintFailedError(); 
        }
        emit GSZTMint(userAddress, toMint);
        return true;
    }


    // :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::: //
    // ::::::::::::::::::::::::: VIEW FUNCTIONS ::::::::::::::::::::::::: //
    // :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::: //


    /// @notice check the current SZT token price
    function viewSZTCurrentPrice() external view override returns(uint256) {
        uint256 SZTCommonRatio = (_commonRatio * SZT_BASE_PRICE * _tokenCounter)/1e18;
        uint256 amountPerToken = (SZT_BASE_PRICE * (1e18)) + SZTCommonRatio;
        return amountPerToken;
    }
    
    /// @notice calculate the SZT token value for the asked amount of SZT tokens
    /// @param issuedSZTTokens: the amount of SZT tokens currently in circulation
    /// @param requiredTokens: issuedSZTTokens + amount of GENZ ERC20 user wishes to purchase
    function calculatePriceSZT(
        uint256 issuedSZTTokens, 
        uint256 requiredTokens
    ) public view override returns(uint256, uint256) {
        uint256 commonRatioSZT = _commonRatio * SZT_BASE_PRICE;
        // NOTE: to avoid check everytime, we preferred to buy the first token.
        // uint256 _required = requiredTokens > 1e18 ? requiredTokens - 1e18 : 1e18 - requiredTokens;
        uint256 tokenDifference = (issuedSZTTokens + (requiredTokens - 1e18));
        uint256 averageDiff = ((commonRatioSZT * tokenDifference) / 2) / 1e18;
        uint256 amountPerToken = SZT_BASE_PRICE_WITH_DEC + averageDiff;
        uint256 amountToBePaid = (amountPerToken * (requiredTokens - issuedSZTTokens))/1e18;
        return (amountPerToken, amountToBePaid);
    }

    /// @notice calculate the common ratio for the GSZT token calculation
    /// @param issuedSZTTokens: amount of SZT tokens currently in circulation
    /// @param alpha: alpha value for the calculation of GSZT token
    /// @param decimals: to calculate the actual alpha value for GSZT tokens 
    function _calculateCommonRatioGSZT(
        uint256 issuedSZTTokens, 
        uint256 alpha, 
        uint256 decimals
    ) private pure returns(uint256) {
        uint256 mantissa = 10 ** decimals;
        uint256 tokenValue = (alpha * SZT_BASE_PRICE * issuedSZTTokens) / mantissa;
        uint256 amountPerToken = SZT_BASE_PRICE_WITH_DEC + tokenValue;
        return amountPerToken;
    }

    /// @notice Burning the GSZT token
    /// @param userAddress: wallet address of the user
    function _burnTokenGSZT(address userAddress) private view returns(uint256) {
        uint256 userBalanceSZT = _tokenSZT.balanceOf(userAddress);
        uint256 amountUnderwritten = _coveragePool.getUnderwriteSZTBalance(userAddress);
        uint256 GSZTAmountToHave = _calculateTokenCountGSZT(userBalanceSZT + amountUnderwritten);
        uint256 GSZTAmountUserHave = _tokenGSZT.balanceOf(userAddress);
        uint256 amountToBeBurned = GSZTAmountUserHave - GSZTAmountToHave;
        return amountToBeBurned;
    }

    /// @notice calculating the GSZT token to be awarded to user based on the amount of SZT token user have
    /// @param issuedSZTTokens: amount of issued SZT tokens to user    
    function _calculateTokenCountGSZT(
        uint256 issuedSZTTokens
    ) private pure returns(uint256) {
        uint256 commonRatio_17_2 = (
            (SZT_BASE_PRICE * 1e36) / 
            _calculateCommonRatioGSZT(issuedSZTTokens, 17, 2)
        );
        uint256 commonRatio_22_6 = (
            (_calculateCommonRatioGSZT(issuedSZTTokens, 22, 6) / 
            (SZT_BASE_PRICE)) - (1e18)
        );
        uint256 GSZTTokenCount = ((commonRatio_17_2 + commonRatio_22_6) * issuedSZTTokens) / 1e18;
        return GSZTTokenCount;
    }

    /// @notice to check the common ratio used in the price calculation of SZT token 
    function getCommonRatio() external view returns (uint256) {
        return _commonRatio;
    }

    // @notice returns the current token counter
    function getTokenCounter() public view returns(uint256) {
        return _tokenCounter;
    }

    // @notice returns the SZT base price with 18 decimals
    function getBasePriceSZT() public pure returns(uint256) {
        return SZT_BASE_PRICE_WITH_DEC;
    }
}