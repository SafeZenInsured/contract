// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/// @title Buy GENZ Contract
/// @author Anshik Bansal <anshik@safezen.finance>

/*

100M GENZ tokens will be minted in supply, fixed capped.
Initial round tokens will be raised at $10M valuation for a sale of /
/ 2M token to raise 200k.
Token sale will be made live on multiple EVM chains including Ethereum, Polygon, Avalanche,
Arbitrum and Optimism.
Token sale for now will not be made on BNB chain.
400k tokens will be offered for sale on each of the EVM chain to raise 40k on each of the chain.

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
    uint256 private _tokenPrice;
    uint256 private _currVersion;
    uint256 private _tokenCounter;
    uint256 private _minWithdrawalPeriod;
    uint256 private constant MULTIPLIER = 1e10;
    uint256 private constant WITHDRAWAL_PERIOD_MULTIPLIER = 8 hours;

    /// _tokenDAI: DAI ERC20 token
    /// _tokenUSDC: USDC ERC20 token
    /// _globalPauseOperation: Global Pause Operations Contract
    IERC20Upgradeable private immutable _tokenDAI;
    IERC20Upgradeable private immutable _tokenGENZ;
    IGlobalPauseOperation private _globalPauseOperation;
    IERC20PermitUpgradeable private immutable _tokenPermitDAI;
    

    struct VersionableInfo {
        uint256 startTime;
        uint256 endTime;
        uint256 distributedAmount;
        uint256 tokenDistributed;
    }

    struct UserInfo {
        bool hasBought;
        uint256 startVersionBlock; 
    }

    struct UserBalanceInfo {
        uint256 boughtTokens;
        uint256 claimedRewards;
    }

    struct StakeInformation {
        bool hasStaked;
        uint256 amount;
        uint256 minWithdrawTime;
    }

    mapping(address => UserInfo) private usersInfo;

    /// versionID => VersionableInfo
    mapping(uint256 => VersionableInfo) private versionableInfo;

    /// userAddress => versionID => UserBalanceInfo
    mapping(address => mapping(uint256 => UserBalanceInfo)) private usersBalanceInfo;

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
    constructor(address tokenDAI, address tokenGENZ) {
        _tokenDAI = IERC20Upgradeable(tokenDAI); 
        _tokenPermitDAI = IERC20PermitUpgradeable(tokenDAI);
        _tokenGENZ = IERC20Upgradeable(tokenGENZ); 
    }

    /// @dev one time function to initialize the contract
    /// @param pauseOperationAddress: address of the Global Pause Operation contract
    function initialize(
        address pauseOperationAddress
    ) external initializer {
        _tokenPrice = 1e17;
        _globalPauseOperation = IGlobalPauseOperation(pauseOperationAddress);
        __BaseUpgradeablePausable_init(_msgSender());
    }

    function updateTokenPrice(uint256 tokenPrice) external onlyAdmin {
        _tokenPrice = tokenPrice;
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
        _tokenPrice *= MULTIPLIER;
        _minWithdrawalPeriod += WITHDRAWAL_PERIOD_MULTIPLIER;
        uint256 amountToBePaid = value * _tokenPrice;
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

    function getVersionID() public view returns(uint256) {
        return _currVersion;
    }

    function getActiveVersionID() internal view returns(uint256[] memory) {
        uint256 activeCount = 0;
        uint256 userStartVersion = usersInfo[_msgSender()].startVersionBlock;
        uint256 currVersion =  getVersionID();
        for(uint256 i = userStartVersion; i <= currVersion;) {
            if (usersBalanceInfo[_msgSender()][i].boughtTokens > 0) {
                ++activeCount;
            }
            ++i;
        }
        uint256[] memory activeVersionID = new uint256[](activeCount);
        uint256 counter = 0;
        for(uint i = userStartVersion; i <= currVersion;) {
            UserBalanceInfo memory userBalance = usersBalanceInfo[_msgSender()][i];
            if (userBalance.boughtTokens > 0) {
                activeVersionID[counter] = i;
            }
            ++counter;
            ++i;
        }
        return activeVersionID;
    }

    function calculateRewards() external view returns(uint256) {
        uint256 userBalance = 0;
        uint256[] memory activeVersionID = getActiveVersionID();
        uint256 startVersionID = activeVersionID[0];
        uint256 userPremiumEarned = 0;
        uint256 counter = 0;
        for(uint256 i = startVersionID; i <= _currVersion;) {
            UserBalanceInfo memory userVersionBalance = usersBalanceInfo[_msgSender()][i];
            if(activeVersionID[counter] == i) {
                if (userVersionBalance.boughtTokens > 0) {
                    userBalance += userVersionBalance.boughtTokens;
                }
                ++counter;
            }
            VersionableInfo storage versionInfo = versionableInfo[i];           
            uint256 duration = versionInfo.endTime - versionInfo.startTime;
            userPremiumEarned += ((duration * userBalance * versionInfo.distributedAmount)/ (versionInfo.tokenDistributed));
            ++i;
        }
        return userPremiumEarned;
    }

    function getCurrentTokenPrice() public view returns(uint256) {
        return _tokenPrice;
    }

    /// @dev returns the token in circulation
    function getGENZTokenCount() public view returns(uint256) {
        return _tokenCounter;
    }
}