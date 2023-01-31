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
    uint256 private _minStakeValue;
    uint256 private _withdrawTimer;
    uint256 public override totalTokensStaked;
    IERC20Upgradeable private immutable _tokenGENZ;

    struct WithdrawWaitPeriod{
        bool ifTimerStarted;
        uint256 GENZTokenCount;
        uint256 canWithdrawTime;
    }

    struct StakerInfo {
        uint256 amountStaked;
        uint256 rewardEarned;
    }

    mapping(address => StakerInfo) private stakers;

    mapping (address => WithdrawWaitPeriod) private checkWaitTime;

    /// [PRODUCTION TODO: _withdrawTimer = timeInDays * 1 days;]
    constructor(
        address tokenAddressGENZ, 
        uint256 timeInDays
    ) {
        _minStakeValue = 1e18;
        _withdrawTimer = timeInDays * 1 minutes;
        _tokenGENZ = IERC20Upgradeable(tokenAddressGENZ);
        
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

    /// [PRODUCTION TODO: _withdrawTimer = timeInDays * 1 days;]
    function setWithdrawTime(uint256 timeInMinutes) external onlyAdmin {
        _withdrawTimer = timeInMinutes * 1 minutes;
        emit UpdatedWithdrawTimer(timeInMinutes);
    }

    function stakeGENZ(uint256 value) public override nonReentrant returns(bool) {
        if (value < _minStakeValue) {
            revert GENZStaking__NotAMinimumStakeAmountError();
        }
        StakerInfo storage staker = stakers[_msgSender()];
        staker.amountStaked += value;
        totalTokensStaked += value;
        bool success = _tokenGENZ.transferFrom(_msgSender(), address(this), value);
        if (!success) {
            revert GENZStaking__TransactionFailedError();
        }
        emit StakedGENZ(_msgSender(), value);
        return true;
    }
    
    // 48 hours waiting period
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
        StakerInfo storage staker = stakers[_msgSender()];
        if (
            (staker.amountStaked < value) || 
            (block.timestamp < checkWaitTime[_msgSender()].canWithdrawTime) || 
            (value > checkWaitTime[_msgSender()].GENZTokenCount)
        ) {
            revert GENZStaking__TransactionFailedError();
        }
        totalTokensStaked -= value;
        staker.amountStaked -= value;
        if (checkWaitTime[_msgSender()].GENZTokenCount == value) {
            checkWaitTime[_msgSender()].ifTimerStarted = false;
        }
        checkWaitTime[_msgSender()].GENZTokenCount -= value;
        bool success = _tokenGENZ.transfer(_msgSender(), value);
        if (!success) {
            revert GENZStaking__TransactionFailedError();
        }
        emit UnstakedGENZ(_msgSender(), value);
        return true;
    }

    function getUserStakedGENZBalance() external view override returns(uint256) {
        return (stakers[_msgSender()].amountStaked > 0 ? stakers[_msgSender()].amountStaked : 0);
    }

    function getStakerRewardInfo() external view returns(uint256) {
        return stakers[_msgSender()].rewardEarned;
    }
}