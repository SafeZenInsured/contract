// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/// @title GENZ Staking Contract
/// @author Anshik Bansal <anshik@safezen.finance>

/// Importing required interfaces
import "./../../interfaces/IBuyGENZ.sol";
import "./../../interfaces/IGENZStaking.sol";
import "@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol";

/// Importing required libraries
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

/// Importing required contracts
import "./../../BaseUpgradeablePausable.sol";

error GENZStaking__TransactionFailedError();
error GENZStaking__NotAMinimumStakeAmountError();

/// NOTE: Staking tokens would be used for activities like flash loans 
/// to generate rewards for the staked users
contract GENZStaking is IGENZStaking, BaseUpgradeablePausable {

    // :::::::::::::: STATE VARIABLES AND DECLARATIONS :::::::::::::::: //

    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 public currVersion;
    uint256 public minStakeValue;
    uint256 public withdrawTimer;
    uint256 public totalTokensStaked;
    IERC20Upgradeable public immutable tokenGENZ;

    struct VersionableInfo {
        uint256 startTime;
        uint256 endTime;
        uint256 distributedAmount;
        uint256 tokenDistributed;
    }

    struct UserInfo {
        bool hasStaked;
        uint256 stakedTokens;
        uint256 startVersionBlock; 
        uint256 claimedRewards;
    }

    struct UserBalanceInfo {
        uint256 stakedTokens;
        uint256 withdrawnTokens;
    }

    struct WithdrawWaitPeriod{
        bool ifTimerStarted;
        uint256 GENZTokenCount;
        uint256 canWithdrawTime;
    }

    mapping(address => UserInfo) public usersInfo;

    mapping (address => WithdrawWaitPeriod) public checkWaitTime;

    /// versionID => VersionableInfo
    mapping(uint256 => VersionableInfo) public versionableInfos;

    /// userAddress => versionID => UserBalanceInfo
    mapping(address => mapping(uint256 => UserBalanceInfo)) public usersBalanceInfo;

    /// [PRODUCTION TODO: withdrawTimer = timeInDays * 1 days;]
    constructor(address tokenAddressGENZ) {
        minStakeValue = 1e18;
        tokenGENZ = IERC20Upgradeable(tokenAddressGENZ);
    }

    function initialize(uint256 timeInDays) external initializer {
        withdrawTimer = timeInDays * 1 minutes;
        __BaseUpgradeablePausable_init(_msgSender());
    }

    /// @dev this function aims to pause the contracts' certain functions temporarily
    function pause() external onlyAdmin {
        _pause();
    }

    /// @dev this function aims to resume the complete contract functionality
    function unpause() external onlyAdmin {
        _unpause();
    }

    function updateMinimumStakeAmount(uint256 value) external onlyAdmin {
        minStakeValue = value;
        emit UpdatedMinStakingAmount(value);
    }

    /// [PRODUCTION TODO: withdrawTimer = timeInHours * 1 hours;]
    function setWithdrawTime(uint256 timeInMinutes) external onlyAdmin {
        withdrawTimer = timeInMinutes * 1 minutes;
        emit UpdatedWithdrawTimer(timeInMinutes);
    }

    function stakeGENZ(uint256 value) public override nonReentrant returns(bool) {
        if (value < minStakeValue) {
            revert GENZStaking__NotAMinimumStakeAmountError();
        }
        ++currVersion;
        UserInfo storage userInfo = usersInfo[_msgSender()];
        if(!userInfo.hasStaked) {
            userInfo.hasStaked = true;
            userInfo.startVersionBlock = currVersion;
        }
        userInfo.stakedTokens += value;
        usersBalanceInfo[_msgSender()][currVersion].stakedTokens = value;        
        totalTokensStaked += value;
        tokenGENZ.safeTransferFrom(_msgSender(), address(this), value);
        emit StakedGENZ(_msgSender(), value);
        return true;
    }
    
    // 2 hours withdrawal period
    function activateWithdrawalTimer(uint256 value) external override returns(bool) {
        if (
            (!(checkWaitTime[_msgSender()].ifTimerStarted)) || 
            (checkWaitTime[_msgSender()].GENZTokenCount < value)
        ) {
            WithdrawWaitPeriod storage waitingTimeCountdown = checkWaitTime[_msgSender()];
            waitingTimeCountdown.ifTimerStarted = true;
            waitingTimeCountdown.GENZTokenCount = value;
            waitingTimeCountdown.canWithdrawTime = withdrawTimer + block.timestamp;
            return true;
        }
        return false;
    }
    
    function withdrawGENZ(uint256 value) external override nonReentrant returns(bool) {
        UserInfo storage userInfo = usersInfo[_msgSender()];
        if (
            (userInfo.stakedTokens < value) || 
            (block.timestamp < checkWaitTime[_msgSender()].canWithdrawTime) || 
            (value > checkWaitTime[_msgSender()].GENZTokenCount)
        ) {
            revert GENZStaking__TransactionFailedError();
        }
        ++currVersion;
        totalTokensStaked -= value;
        userInfo.stakedTokens -= value;
        usersBalanceInfo[_msgSender()][currVersion].withdrawnTokens = value;
        if (checkWaitTime[_msgSender()].GENZTokenCount == value) {
            checkWaitTime[_msgSender()].ifTimerStarted = false;
        }
        checkWaitTime[_msgSender()].GENZTokenCount -= value;
        tokenGENZ.safeTransfer(_msgSender(), value);
        emit UnstakedGENZ(_msgSender(), value);
        return true;
    }


    function getActiveVersionID() internal view returns(uint256[] memory) {
        uint256 activeCount = 0;
        uint256 userStartVersion = usersInfo[_msgSender()].startVersionBlock;
        uint256 currVersion_ =  currVersion;
        for(uint256 i = userStartVersion; i <= currVersion_;) {
            if (usersBalanceInfo[_msgSender()][i].stakedTokens > 0) {
                ++activeCount;
            }
            if (usersBalanceInfo[_msgSender()][i].withdrawnTokens > 0) {
                ++activeCount;
            }
            ++i;
        }
        uint256[] memory activeVersionID = new uint256[](activeCount);
        uint256 counter = 0;
        for(uint i = userStartVersion; i <= currVersion_;) {
            UserBalanceInfo memory userBalance = usersBalanceInfo[_msgSender()][i];
            if(userBalance.stakedTokens > 0) {
                activeVersionID[counter] = i;
            }
            if(userBalance.withdrawnTokens > 0) {
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
        for(uint256 i = startVersionID; i <= currVersion;) {
            UserBalanceInfo memory userVersionBalance = usersBalanceInfo[_msgSender()][i];
            if(activeVersionID[counter] == i) {
                if (userVersionBalance.stakedTokens > 0) {
                    userBalance += userVersionBalance.stakedTokens;
                }
                else {
                    userBalance -= userVersionBalance.withdrawnTokens;
                }
                ++counter;
            }
            VersionableInfo storage versionInfo = versionableInfos[i];           
            uint256 duration = versionInfo.endTime - versionInfo.startTime;
            userPremiumEarned += ((duration * userBalance * versionInfo.distributedAmount)/ (versionInfo.tokenDistributed));
            ++i;
        }
        return userPremiumEarned;
    }
}