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
    uint256 private _currVersion;
    uint256 private _minStakeValue;
    uint256 private _withdrawTimer;
    uint256 public override totalTokensStaked;
    IERC20Upgradeable private immutable _tokenGENZ;

    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// TODO: Versionable Info data to be included in functions
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

    mapping (address => WithdrawWaitPeriod) private checkWaitTime;

    mapping(address => UserInfo) private usersInfo;

    /// versionID => VersionableInfo
    mapping(uint256 => VersionableInfo) private versionableInfos;

    /// userAddress => versionID => UserBalanceInfo
    mapping(address => mapping(uint256 => UserBalanceInfo)) private usersBalanceInfo;

    /// [PRODUCTION TODO: _withdrawTimer = timeInDays * 1 days;]
    constructor(
        address tokenAddressGENZ
    ) {
        _minStakeValue = 1e18;
        _tokenGENZ = IERC20Upgradeable(tokenAddressGENZ);
    }

    function initialize(uint256 timeInDays) external initializer {
        _withdrawTimer = timeInDays * 1 minutes;
        __BaseUpgradeablePausable_init(_msgSender());
    }

    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }

    function updateMinimumStakeAmount(uint256 value) external onlyAdmin {
        _minStakeValue = value;
        emit UpdatedMinStakingAmount(value);
    }

    /// [PRODUCTION TODO: _withdrawTimer = timeInHours * 1 hours;]
    function setWithdrawTime(uint256 timeInMinutes) external onlyAdmin {
        _withdrawTimer = timeInMinutes * 1 minutes;
        emit UpdatedWithdrawTimer(timeInMinutes);
    }

    function stakeGENZ(uint256 value) public override nonReentrant returns(bool) {
        if (value < _minStakeValue) {
            revert GENZStaking__NotAMinimumStakeAmountError();
        }
        ++_currVersion;
        UserInfo storage userInfo = usersInfo[_msgSender()];
        if(!userInfo.hasStaked) {
            userInfo.hasStaked = true;
            userInfo.startVersionBlock = _currVersion;
        }
        userInfo.stakedTokens += value;
        usersBalanceInfo[_msgSender()][_currVersion].stakedTokens = value;        
        totalTokensStaked += value;
        _tokenGENZ.safeTransferFrom(_msgSender(), address(this), value);
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
            waitingTimeCountdown.canWithdrawTime = _withdrawTimer + block.timestamp;
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
        ++_currVersion;
        totalTokensStaked -= value;
        userInfo.stakedTokens -= value;
        usersBalanceInfo[_msgSender()][_currVersion].withdrawnTokens = value;
        if (checkWaitTime[_msgSender()].GENZTokenCount == value) {
            checkWaitTime[_msgSender()].ifTimerStarted = false;
        }
        checkWaitTime[_msgSender()].GENZTokenCount -= value;
        _tokenGENZ.safeTransfer(_msgSender(), value);
        emit UnstakedGENZ(_msgSender(), value);
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
        for(uint i = userStartVersion; i <= currVersion;) {
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
        for(uint256 i = startVersionID; i <= _currVersion;) {
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

    function getUserStakedGENZBalance() external view override returns(uint256) {
        return (usersInfo[_msgSender()].stakedTokens > 0 ? usersInfo[_msgSender()].stakedTokens : 0);
    }

    function getStakerClaimedRewardInfo() external view returns(uint256) {
        return usersInfo[_msgSender()].claimedRewards;
    }
}