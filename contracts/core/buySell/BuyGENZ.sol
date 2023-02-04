// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/// @title Buy GENZ Contract
/// @author Anshik Bansal <anshik@safezen.finance>

/*

10M GENZ tokens will be minted in supply, fixed capped.
Initial round tokens will be raised at $10M valuation for a sale of /
/ 200k token to raise 200k.
Token sale will be made live on multiple EVM chains including Ethereum, Polygon, Avalanche,
Arbitrum and Optimism.
Token sale for now will not be made on BNB chain.
40k tokens will be offered for sale on each of the EVM chain to raise 40k on each of the chain.

GENZ Token Utilities:
    1. Similar to traditional markets, earn dividend just by holding GENZ token every second.
    2. Similar to traditional markets, there is no need to stake GENZ tokens to ripe the dividend rewards.
    3. It will derive its value from the project's operation and profit generation.
    4. It will be used to reward the bug bounty hunters.
    5. It will also be awarded during the claim governance, so as users participating in the /
       / claim settlement process will earn free GENZ tokens as participation rewards.
    6. At the same time, GSZT tokens will be awarded to participants to close insured user's  /
       / pay-as-you-go insurance streams after the insurance period gets over.

100M GENZ token supply will be as:
    - 20M on each of the following chain: Ethereum, Polygon, Avalanche, Arbitrum and Optimism.
    - In the later stages, when we'll integrate more chains, then GENZ tokens will be burned /
      accordingly to ensure capped 100M GENZ token supply. 

*/

// Importing interfaces
import "./../../interfaces/IBuyGENZ.sol";
import "./../../interfaces/IERC20Extended.sol";
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

    /// _tokenCounter: GENZ ERC20 tokens in circulation
    /// _currVersion: 
    uint256 private _saleCap;
    uint256 private immutable _commonRatio;
    uint256 private _tokenCounter;
    uint256 private _baseSalePrice;
    uint256 private _basePriceWithDec;
    uint256 private _minWithdrawalPeriod;
    uint256 private constant WITHDRAWAL_PERIOD_MULTIPLIER = 8 hours;

    /// _tokenDAI: DAI ERC20 token
    /// _tokenUSDC: USDC ERC20 token
    /// _globalPauseOperation: Global Pause Operations Contract
    IERC20Upgradeable private immutable _tokenDAI;
    IERC20Upgradeable private immutable _tokenGENZ;
    IGlobalPauseOperation private _globalPauseOperation;
    IERC20PermitUpgradeable private immutable _tokenPermitDAI;

    struct StakeInformation {
        bool hasStaked;
        uint256 amount;
        uint256 minWithdrawTime;
    }

    mapping(address => StakeInformation) private stakingInformation;
    
    modifier ifNotPaused() {
        require(
            (paused() != true) && 
            (_globalPauseOperation.isPaused() != true));
        _;
    }

    /// @dev initializing _tokenDAI
    /// @param tokenDAI: address of the DAI token
    /// @custom:oz-upgrades-unsafe-allow-constructor
    constructor(uint256 value, uint256 decimals, address tokenDAI, address tokenGENZ) {
        _tokenDAI = IERC20Upgradeable(tokenDAI); 
        _tokenGENZ = IERC20Upgradeable(tokenGENZ); 
        _tokenPermitDAI = IERC20PermitUpgradeable(tokenDAI);
        _commonRatio = (value * 10e17) / (10 ** decimals); // Immutable
    }

    /// @dev one time function to initialize the contract
    /// @param pauseOperationAddress: address of the Global Pause Operation contract
    function initialize(
        address pauseOperationAddress
    ) external initializer {
        _baseSalePrice = 1;
        _basePriceWithDec = 1e18;
        _globalPauseOperation = IGlobalPauseOperation(pauseOperationAddress);
        __BaseUpgradeablePausable_init(_msgSender());
    }

    function updateBaseSalePrice(uint256 tokenPrice) external onlyAdmin {
        _baseSalePrice = tokenPrice;
        _basePriceWithDec = tokenPrice * 1e18;
    }

    function updateMinimumWithdrawalPeriod(uint256 valueInDays) external onlyAdmin {
        _minWithdrawalPeriod = valueInDays * 1 days;
    }

    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }

    /// @dev 
    /// @param value: amount of SZT tokens user wishes to purchase
    function buyGENZToken(
        uint256 value,
        uint deadline, 
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant ifNotPaused returns(bool) {
        if (value < 1e18) {
            revert BuySellGENZ__LowAmountError();
        }
        _minWithdrawalPeriod += WITHDRAWAL_PERIOD_MULTIPLIER;
        (/* uint256 amountPerToken */, uint256 amountToBePaid) = calculatePriceGENZ(
            _tokenCounter, _tokenCounter + value);
        if (amountToBePaid > _tokenDAI.balanceOf(_msgSender())) {
            revert BuySellGENZ__InsufficientBalanceError();
        }
        StakeInformation storage userStakeInformation = stakingInformation[_msgSender()];
        userStakeInformation.amount += value;
        userStakeInformation.hasStaked = true;
        userStakeInformation.minWithdrawTime = block.timestamp + _minWithdrawalPeriod;
        _tokenPermitDAI.safePermit(_msgSender(), address(this), amountToBePaid, deadline, v, r, s);
        _tokenDAI.safeTransferFrom(_msgSender(), address(this), amountToBePaid);
        return true;
    }

    function calculatePriceGENZ(
        uint256 issuedTokensGENZ, 
        uint256 requiredTokens
    ) public view returns(uint256, uint256) {
        uint256 commonRatioGENZ = _commonRatio * _baseSalePrice;
        uint256 tokenDifference = (issuedTokensGENZ + (requiredTokens - 1e18));
        uint256 averageDiff = ((commonRatioGENZ * tokenDifference) / 2) / 1e18;
        uint256 amountPerToken = _basePriceWithDec + averageDiff;
        uint256 amountToBePaid = (amountPerToken * (requiredTokens - issuedTokensGENZ))/1e18;
        return (amountPerToken, amountToBePaid);
    }

    error BuyGENZ__TransactionFailedError();
    function withdrawStakedToken() external {
        if (!stakingInformation[_msgSender()].hasStaked) {
            revert BuyGENZ__TransactionFailedError();
        }
        if (stakingInformation[_msgSender()].minWithdrawTime > block.timestamp ) {
            revert BuyGENZ__TransactionFailedError();
        }
        uint256 amountStaked = stakingInformation[_msgSender()].amount;
        stakingInformation[_msgSender()].hasStaked = false;
        stakingInformation[_msgSender()].amount = 0;
        _tokenGENZ.safeTransfer(_msgSender(), amountStaked);
    }

    function getCurrentTokenPrice() public view returns(uint256) {
        (uint256 amountPerToken, /*uint256 amountToBePaid*/) = calculatePriceGENZ(
            _tokenCounter, _tokenCounter + 1e18);
        return amountPerToken;
    }

    /// @dev returns the token in circulation
    function getGENZTokenCount() public view returns(uint256) {
        return _tokenCounter;
    }
}