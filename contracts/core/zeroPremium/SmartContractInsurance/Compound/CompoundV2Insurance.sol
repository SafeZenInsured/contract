// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/// @title Compound Zero Premium Insurance Contract
/// @author Anshik Bansal <anshik@safezen.finance>

/// Importing required interfaces
import "./../../../../interfaces/Compound/ICErc20.sol";
import "./../../../../interfaces/IGlobalPauseOperation.sol";
import "./../../../../interfaces/ISmartContractZPController.sol";
import "./../../../../interfaces/Compound/ICompoundImplementation.sol";

/// Importing required libraries
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

/// Importing required contracts
import "./../../../../BaseUpgradeablePausable.sol";

/// Report any bug or issues at:
/// @custom:security-contact anshik@safezen.finance
contract CompoundV2Insurance is ICompoundImplementation, BaseUpgradeablePausable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeERC20Upgradeable for IERC20PermitUpgradeable;

    uint256 private _protocolID;
    uint256 private _initVersion;
    uint256 private _childVersion;
    ISmartContractZPController private _zpController;
    IGlobalPauseOperation private _globalPauseOperation;
    
    struct UserInfo {
        bool isActiveInvested;
        uint256 startVersionBlock;
    }

    struct UserTransactionInfo {
        uint256 depositedAmount;
        uint256 withdrawnAmount;
    }

    struct RewardInfo {
        uint256 rewardTokenBalance;
        uint256 amountToBeDistributed;
    }

    /// Maps ChildVersion => ParentVersion
    mapping(uint256 => uint256) private parentVersionInfo;
    /// Maps --> User Address => Reward Token Address => UserInfo struct
    mapping(address => mapping(address => UserInfo)) private usersInfo;
    /// Maps --> User Address => Reward Token Address => ChildVersion => UserTransactionInfo
    mapping(address => mapping(address => mapping(uint256 => UserTransactionInfo))) private userTransactionInfo;

    /// Maps reward address => Child Version => reward balance
    mapping(address => mapping(uint256 => RewardInfo)) private rewardInfo;

    mapping(address => uint256) private globalRewardTokenBalance;

    modifier ifNotPaused() {
        require(
            (paused() != true) && 
            (_globalPauseOperation.isPaused() != true));
        _;
    }

    function initialize(address pauseOperationAddress) external initializer {
        _globalPauseOperation = IGlobalPauseOperation(pauseOperationAddress);
        __BaseUpgradeablePausable_init(_msgSender());
    }

    function init( 
        address _controllerAddress,
        string memory protocolName,
        address deployedAddress,
        uint256 protocolID
    ) external onlyAdmin {
        if (_initVersion > 0) {
            revert Compound_ZP__ImmutableChangesError();
        }
        ++_initVersion;
        _zpController = ISmartContractZPController(_controllerAddress);
        (string memory _protocolName, address _protocolAddress) = _zpController.getProtocolInfo(protocolID);
        if (_protocolAddress != deployedAddress) {
            revert Compound_ZP__WrongInfoEnteredError();
        }
        if(keccak256(abi.encodePacked(_protocolName)) != keccak256(abi.encodePacked(protocolName))) {
            revert Compound_ZP__WrongInfoEnteredError();
        }
        _protocolID = protocolID;
    }

    function liquidateTokens(
        address[] memory tokenAddresses,
        address[] memory rewardTokenAddresses,
        address claimSettlementAddress,
        uint256 protocolRiskCategory,
        uint256 liquidationPercent
    ) external onlyAdmin {
        uint256 tokenCount = rewardTokenAddresses.length;
        for(uint256 i = 0; i < tokenCount;) {
            if(_zpController.getProtocolRiskCategory(_protocolID) == protocolRiskCategory) {
                uint256 liquidatedAmount = (
                    (liquidationPercent * globalRewardTokenBalance[rewardTokenAddresses[i]]) / 100
                );
                globalRewardTokenBalance[rewardTokenAddresses[i]] -= liquidatedAmount;
                IERC20Upgradeable token = IERC20Upgradeable(tokenAddresses[i]);
                uint256 balanceBeforeRedeem = token.balanceOf(address(this));
                uint256 redeemResult = ICErc20(rewardTokenAddresses[i]).redeemUnderlying(liquidatedAmount);
                if (redeemResult != 0){
                    revert Compound_ZP__TransactionFailedError();
                }
                uint256 balanceAfterRedeem = token.balanceOf(address(this));
                uint256 amountLiquidated = balanceAfterRedeem - balanceBeforeRedeem;
                token.safeTransfer(claimSettlementAddress, amountLiquidated);
            }
            ++i;
        }
    }

    function supplyToken(
        address tokenAddress, 
        address rewardTokenAddress, 
        uint256 amount,
        uint256 deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external override nonReentrant returns(bool) {
        if (amount < 1e10) {
            revert Compound_ZP__LowSupplyAmountError();
        }
        ++_childVersion;
        uint256 currParentVersion =  _zpController.latestVersion();
        parentVersionInfo[_childVersion] = currParentVersion;

        IERC20Upgradeable token = IERC20Upgradeable(tokenAddress);
        IERC20Upgradeable rewardToken = IERC20Upgradeable(rewardTokenAddress);
        IERC20PermitUpgradeable tokenWithPermit = IERC20PermitUpgradeable(tokenAddress);

        if (!usersInfo[_msgSender()][rewardTokenAddress].isActiveInvested) {
            usersInfo[_msgSender()][rewardTokenAddress].startVersionBlock = _childVersion;
            usersInfo[_msgSender()][rewardTokenAddress].isActiveInvested = true;
        }
        uint256 balanceBeforeSupply = rewardToken.balanceOf(address(this));
        tokenWithPermit.safePermit(_msgSender(), address(this), amount, deadline, v, r, s);
        token.safeTransferFrom(_msgSender(), address(this), amount);
        token.safeIncreaseAllowance(rewardTokenAddress, amount);
        
        uint mintResult = ICErc20(rewardTokenAddress).mint(amount);
        if (mintResult != 0){
            revert Compound_ZP__TransactionFailedError();
        }
        uint256 balanceAfterSupply = rewardToken.balanceOf(address(this));
        updateInfo(rewardTokenAddress, balanceAfterSupply, balanceBeforeSupply);
        emit SuppliedToken(_msgSender(), tokenAddress, amount);
        return true;
    }

    function updateInfo(
        address rewardTokenAddress, 
        uint256 balanceAfterSupply,
        uint256 balanceBeforeSupply
    ) private {
        uint256 tokenRewarded = (balanceAfterSupply - balanceBeforeSupply);
        rewardInfo[rewardTokenAddress][_childVersion].rewardTokenBalance += tokenRewarded;
        rewardInfo[rewardTokenAddress][_childVersion - 1].amountToBeDistributed = (
            balanceBeforeSupply - 
            rewardInfo[rewardTokenAddress][_childVersion - 1].rewardTokenBalance
        );
        userTransactionInfo[_msgSender()][rewardTokenAddress][_childVersion].depositedAmount += tokenRewarded;
        globalRewardTokenBalance[rewardTokenAddress] += tokenRewarded;
    }

    function withdrawToken(
        address tokenAddress, 
        address rewardTokenAddress, 
        uint256 amount
    ) external override nonReentrant returns(bool) {
        ++_childVersion;
        uint256 userBalance = calculateUserBalance(rewardTokenAddress);

        if(userBalance < amount) {
            revert Compound_ZP__LowAmountError();
        }
        IERC20Upgradeable token = IERC20Upgradeable(tokenAddress);
        IERC20Upgradeable rewardToken = IERC20Upgradeable(rewardTokenAddress);

        uint256 balanceBeforeWithdraw = rewardToken.balanceOf(address(this));
        rewardInfo[rewardTokenAddress][_childVersion].rewardTokenBalance -= amount;
        rewardInfo[rewardTokenAddress][_childVersion - 1].amountToBeDistributed = (
            balanceBeforeWithdraw - 
            rewardInfo[rewardTokenAddress][_childVersion - 1].rewardTokenBalance
        );

        userTransactionInfo[_msgSender()][rewardTokenAddress][_childVersion].withdrawnAmount += amount;
        if (amount == userBalance) {
            usersInfo[_msgSender()][rewardTokenAddress].isActiveInvested = false;
        }

        uint256 balanceBeforeRedeem = token.balanceOf(address(this));
        uint256 redeemResult = ICErc20(rewardTokenAddress).redeemUnderlying(amount);
        if (redeemResult != 0){
            revert Compound_ZP__TransactionFailedError();
        }
        uint256 balanceAfterRedeem = token.balanceOf(address(this));
        uint256 amountToBePaid = (balanceAfterRedeem - balanceBeforeRedeem);
        globalRewardTokenBalance[rewardTokenAddress] -= amount;
        token.safeTransfer(_msgSender(), amountToBePaid);
        return true;
    }

    function calculateUserBalance(
        address rewardTokenAddress
    ) public view override returns(uint256) {
        uint256 userBalance = 0;
        uint256 userRewardBalance = 0;
        uint256 userStartVersion = usersInfo[_msgSender()][rewardTokenAddress].startVersionBlock;
        uint256 currVersion = _childVersion;
        uint256 riskPoolCategory = 0;
        uint256 parentVersion = 0;
        for(uint i = userStartVersion; i < currVersion;) {
            UserTransactionInfo memory userBalanceInfo = userTransactionInfo[_msgSender()][rewardTokenAddress][i];
            uint256 userDepositedBalance = userBalanceInfo.depositedAmount;
            uint256 userWithdrawnBalance = userBalanceInfo.withdrawnAmount;
            if (userDepositedBalance > 0) {
                userBalance += userDepositedBalance;
            }
            if (userWithdrawnBalance > 0) {
                userBalance -= userWithdrawnBalance;
            }
            uint256 rewardEarned = (
                (userBalance * rewardInfo[rewardTokenAddress][i].amountToBeDistributed) / 
                rewardInfo[rewardTokenAddress][i].rewardTokenBalance
            );
            userRewardBalance += rewardEarned;
            uint256 _parentVersion = _zpController.latestVersion();
            /// this check ensures that if liquidation has happened on a particular parent version,
            /// then user needs to liquidated once, not again and again for each child version loop call.
            if(parentVersion != _parentVersion) {
                parentVersion = _parentVersion;
                if (_zpController.ifProtocolUpdated(_protocolID, parentVersion)) {
                    riskPoolCategory = _zpController.getProtocolRiskCategory(_protocolID, parentVersion);
                }
                if (_zpController.isRiskPoolLiquidated(parentVersion, riskPoolCategory)) {
                    userBalance = ((userBalance * _zpController.getLiquidationFactor(parentVersion)) / 100);
                }
            }
            ++i; 
        }
        userBalance += userRewardBalance;
        return userBalance;
    }
}