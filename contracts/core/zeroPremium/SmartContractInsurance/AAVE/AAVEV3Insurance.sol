// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/// @title AAVE Zero Premium Insurance Contract
/// @author Anshik Bansal <anshik@safezen.finance>

/// Importing required interfaces
import "./../../../../interfaces/IGlobalPauseOperation.sol";
import "./../../../../interfaces/AAVE/IAAVEV3Interface.sol";
import "./../../../../interfaces/AAVE/IAAVEImplementation.sol"; 
import "./../../../../interfaces/ISmartContractZPController.sol"; 

/// Importing required libraries
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

/// Importing required contracts
import "./../../../../BaseUpgradeablePausable.sol";

/// Report any bug or issues at:
/// @custom:security-contact anshik@safezen.finance

// TODO: ADDING EVENTS
contract AAVEV3Insurance is IAAVEImplementation, BaseUpgradeablePausable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeERC20Upgradeable for IERC20PermitUpgradeable;

    uint256 private _protocolID;  
    uint256 private _initVersion;
    uint256 private _childVersion;
    IAAVEV3Interface private _interfaceAAVEV3;
    ISmartContractZPController private _zpController;
    IGlobalPauseOperation private _globalPauseOperation;

    /// @dev: Struct storing the user info
    /// @param isActiveInvested: checks if the user has already deposited funds in AAVE via us
    /// @param startVersionBlock: keeps a record with which version user started using our protocol
    struct UserInfo {
        bool isActiveInvested;
        uint256 startVersionBlock;
    }

    struct UserTransactionInfo {
        uint256 depositedAmount;
        uint256 withdrawnAmount;
    }

    struct RewardInfo {
        uint256 tokenBalance;
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

    mapping(address => uint256) private globalTokenBalance;

    /// @dev this modifier checks if the contract function call has to be paused temporarily
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

    /// @dev Initialize this function first before running any other function
    /// @dev Registers the AAVE protocol in the Zero Premium Controller protocol list
    /// @param protocolName: name of the protocol: AAVE
    /// @param deployedAddress: address of the AAVE lending pool
    /// @dev initializing contract with AAVE v3 lending pool address and Zero Premium controller address
    /// @param _lendingAddress: AAVE v3 lending address
    /// @param _controllerAddress: Zero Premium Controller address
    function init(
        address _lendingAddress, 
        address _controllerAddress,
        string memory protocolName,
        address deployedAddress,
        uint256 protocolID
    ) external onlyAdmin {
        if (_initVersion > 0) {
            revert AAVE_ZP__ImmutableChangesError(78);
        }
        ++_initVersion;
        _interfaceAAVEV3 = IAAVEV3Interface(_lendingAddress);
        _zpController = ISmartContractZPController(_controllerAddress);
        (string memory _protocolName, address _protocolAddress) = _zpController.getProtocolInfo(protocolID);
        if (_protocolAddress != deployedAddress) {
            revert AAVE_ZP__WrongInfoEnteredError(85);
        }
        if(keccak256(abi.encodePacked(_protocolName)) != keccak256(abi.encodePacked(protocolName))) {
            revert AAVE_ZP__WrongInfoEnteredError(88);
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
                    (liquidationPercent * globalTokenBalance[rewardTokenAddresses[i]]) / 100
                );
                globalTokenBalance[rewardTokenAddresses[i]] -= liquidatedAmount;
                IERC20Upgradeable token = IERC20Upgradeable(tokenAddresses[i]);
                IERC20Upgradeable rewardToken = IERC20Upgradeable(rewardTokenAddresses[i]);
                rewardToken.safeIncreaseAllowance(address(_interfaceAAVEV3), liquidatedAmount);
                uint256 balanceBeforeRedeem = token.balanceOf(address(this));
                _interfaceAAVEV3.withdraw(tokenAddresses[i], liquidatedAmount, address(this));
                uint256 balanceAfterRedeem = token.balanceOf(address(this));
                uint256 amountLiquidated = balanceAfterRedeem - balanceBeforeRedeem;
                token.safeTransfer(claimSettlementAddress, amountLiquidated);
            }
            ++i;
        }
    }


    /// @dev supply function to supply token to the AAVE v3 Pool
    /// In the case of AAVE V3, tokenBalance will be stored, instead of reward token balance
    /// as during the withdraw, AAVE function asks for token address, not aToken address.
    /// @param tokenAddress: token address of the supplied token, e.g. DAI
    /// @param rewardTokenAddress: token address of the received token, e.g. aDAI
    /// @param amount: amount of the tokens supplied
    function supplyToken(
        address tokenAddress, 
        address rewardTokenAddress, 
        uint256 amount,
        uint256 deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external override nonReentrant returns (bool) {
        if (amount < 1e10) {
            revert AAVE_ZP__LowSupplyAmountError(117);
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
        token.safeIncreaseAllowance(address(_interfaceAAVEV3), amount);

        _interfaceAAVEV3.supply(tokenAddress, amount, address(this), 0);
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
        uint256 tokenSupplied = balanceAfterSupply - balanceBeforeSupply;
        rewardInfo[rewardTokenAddress][_childVersion].tokenBalance += tokenSupplied;
        rewardInfo[rewardTokenAddress][_childVersion - 1].amountToBeDistributed = (
            balanceBeforeSupply - 
            rewardInfo[rewardTokenAddress][_childVersion - 1].tokenBalance
        );
        userTransactionInfo[_msgSender()][rewardTokenAddress][_childVersion].depositedAmount += tokenSupplied;
        globalTokenBalance[rewardTokenAddress] += tokenSupplied;
    }

    /// @dev to withdraw the tokens from the AAVE v3 lending pool
    /// @param tokenAddress: token address of the supplied token, e.g. DAI
    /// @param rewardTokenAddress: token address of the received token, e.g. aDAI
    /// @param amount: token amount to be withdrawn, not reward token amount in AAVE.
    function withdrawToken(
        address tokenAddress, 
        address rewardTokenAddress, 
        uint256 amount
    ) external ifNotPaused nonReentrant override returns(bool) {
        ++_childVersion;
        uint256 userBalance = calculateUserBalance(rewardTokenAddress);

        if(userBalance < amount) {
            revert AAVE_ZP__LowAmountError(155);
        }
        IERC20Upgradeable token = IERC20Upgradeable(tokenAddress);
        IERC20Upgradeable rewardToken = IERC20Upgradeable(rewardTokenAddress);

        uint256 balanceBeforeWithdraw = rewardToken.balanceOf(address(this));
        rewardInfo[rewardTokenAddress][_childVersion].tokenBalance -= amount;
        rewardInfo[rewardTokenAddress][_childVersion - 1].amountToBeDistributed = (
            balanceBeforeWithdraw - 
            rewardInfo[rewardTokenAddress][_childVersion - 1].tokenBalance
        );

        userTransactionInfo[_msgSender()][rewardTokenAddress][_childVersion].withdrawnAmount += amount;
        if (amount == userBalance) {
            usersInfo[_msgSender()][rewardTokenAddress].isActiveInvested = false;
        }
        globalTokenBalance[rewardTokenAddress] -= amount;
        IERC20Upgradeable(rewardTokenAddress).safeIncreaseAllowance(address(_interfaceAAVEV3), amount);
        uint256 balanceBeforeRedeem = token.balanceOf(address(this));
        _interfaceAAVEV3.withdraw(tokenAddress, amount, address(this));
        uint256 balanceAfterRedeem = token.balanceOf(address(this));
        uint256 amountToBePaid = (balanceAfterRedeem - balanceBeforeRedeem);
        token.safeTransfer(_msgSender(), amountToBePaid);
        emit WithdrawnToken(_msgSender(), tokenAddress, amountToBePaid);
        return true;
    }
    
    /// @dev calculates the user balance
    /// @param rewardTokenAddress: token address of the token received, e.g. aDAI
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
                rewardInfo[rewardTokenAddress][i].tokenBalance
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