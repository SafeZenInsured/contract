// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/// @title Buy GENZ Contract
/// @author Anshik Bansal <anshik@safezen.finance>

/*

GENZ Token Utilities:
    1. Similar to traditional markets, earn dividend just by holding GENZ token every second.
    2. Similar to traditional markets, there is no need to stake GENZ tokens to ripe the dividend rewards.
    3. It will derive its value from the project's operation and profit generation.
    4. It will be used to reward the bug bounty hunters.
    5. It will also be awarded during the claim governance, so as users would participate in the /
       / claim settlement process to earn free GENZ tokens as participation rewards.
    
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
    /// _tokenCounter: GENZ ERC20 tokens in circulation
    /// _tokenDAI: DAI ERC20 token
    /// _tokenUSDC: USDC ERC20 token
    /// _globalPauseOperation: Global Pause Operations Contract
    uint256 private _tokenCounter;
    uint256 private _tokenPrice;
    uint256 private _currVersion;
    IERC20Upgradeable private immutable _tokenDAI;
    IERC20Upgradeable private immutable _tokenUSDC;
    IGlobalPauseOperation private _globalPauseOperation;

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

    mapping(address => UserInfo) private usersInfo;

    /// versionID => VersionableInfo
    mapping(uint256 => VersionableInfo) private versionableInfo;

    /// userAddress => versionID => UserBalanceInfo
    mapping(address => mapping(uint256 => UserBalanceInfo)) private usersBalanceInfo;
    
    modifier ifNotPaused() {
        require(
            (paused() != true) && 
            (_globalPauseOperation.isPaused() != true));
        _;
    }

    /// @dev initializing _tokenDAI
    /// @param tokenDAI: address of the DAI token
    /// @custom:oz-upgrades-unsafe-allow-constructor
    constructor(address tokenDAI, address tokenUSDC) {
        _tokenDAI = IERC20Upgradeable(tokenDAI); 
        _tokenUSDC = IERC20Upgradeable(tokenUSDC); 
    }

    /// @dev one time function to initialize the contract
    /// @param pauseOperationAddress: address of the Global Pause Operation contract
    function initialize(
        address pauseOperationAddress
    ) external initializer {
        _globalPauseOperation = IGlobalPauseOperation(pauseOperationAddress);
        _tokenCounter = 0;
        __BaseUpgradeablePausable_init(_msgSender());
    }

    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }

    /// @dev 
    /// @param value: amount of SZT tokens user wishes to purchase
    function buyGENZToken(uint256 value) external nonReentrant ifNotPaused returns(bool) {
        if (value < 1e18) {
            revert BuySellGENZ__LowAmountError();
        }
        /// when someone purchases tokens, check how much platform has earned and update
        /// distributed amount to previous version block
        return true;
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

    function getTokenPrice() external view returns(uint256) {
        
        return 1;
    }

    /// @dev returns the token in circulation
    function getGENZTokenCount() public view returns(uint256) {
        return _tokenCounter;
    }
}