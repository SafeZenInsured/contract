// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/// @title Venus Zero Premium Insurance Contract
/// @author Anshik Bansal <anshik@safezen.finance>

/// Importing required interfaces
import "./../../../../interfaces/Compound/ICErc20.sol";
import "./../../../../interfaces/Compound/IComptroller.sol";
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

    /// protocolID: unique protocol ID
    /// childEpoch: time interval between any new activity recorded, i.e. supply, withdraw or liquidate
    /// initVersion: counter to initialize the init one-time function, max value can be 1.
    /// PLATFORM_FEE: platform fee on the profit earned
    uint256 public protocolID;
    uint256 public childEpoch;
    uint256 public initVersion;
    uint256 public constant PLATFORM_FEE = 90;

    /// tokenComp: ERC20 COMP token interface
    /// compoundComptroller: Compound Comptroller contract interface
    /// zpController: Zero Premium contract interface
    /// globalPauseOperation: Global Pause Operation contract interface 
    IERC20Upgradeable public tokenComp;
    IComptroller public compoundComptroller;
    ISmartContractZPController public zpController;
    IGlobalPauseOperation public globalPauseOperation;

    /// @notice stores important user-related info
    /// isActiveInvested: checks if the user is actively invested or not
    /// rewardWithdrawn: amount of reward token user has withdrawn
    /// startChildEpoch: epoch number when user first interacted with the contract
    /// previousChildEpoch: user's last contract interaction epoch number
    struct UserInfo {
        bool isActiveInvested;
        uint256 rewardWithdrawn;
        uint256 startChildEpoch;
        uint256 previousChildEpoch;
    }

    /// @notice stores information related to the specific epoch number
    /// cTokenBalance: "cumulative" cToken balance
    /// rewardDistributionAmount: reward amount collected for the specific epoch 
    struct EpochSpecificInfo {
        uint256 cTokenBalance;
        uint256 rewardDistributionAmount;
    }

    /// Maps :: childEpoch(uint256) => zeroPremiumControllerEpoch(uint256)
    mapping(uint256 => uint256) private parentEpoch;
    
    /// Maps :: cTokenAddress(address) => previousChildEpoch(uint256)
    mapping(address => uint256) private previousChildEpoch;
    
    /// Maps :: userAddress(address) => cTokenAddress(address) => UserInfo(struct)
    mapping(address => mapping(address => UserInfo)) private usersInfo;
    
    /// Maps :: cTokenAddress(address) => childEpich(uint256) => EpochSpecificInfo(struct)
    mapping(address => mapping(uint256 => EpochSpecificInfo)) private epochsInfo;
    
    /// Maps :: userAddress(address) => cTokenAddress(uint256) => childEpoch(uint256) => cTokenUserBalance(uint256)
    mapping(address => mapping(address => mapping(uint256 => uint256))) private userChildEpochBalance;


    /// @notice this modifier checks if the contracts' certain function calls has to be paused temporarily
    modifier ifNotPaused() {
        require(
            (paused() != true) && 
            (globalPauseOperation.isPaused() != true));
        _;
    }

    /// @notice initialize function, called during the contract initialization
    /// addressComp: ERC20 COMP token address
    /// addressPauseOperation: Global Pause Operation contract address
    /// addressCompComptroller: Compound Comptroller contract address 
    function initialize(
        address addressComp,
        address addressPauseOperation,
        address addressCompComptroller
    ) external initializer {
        compoundComptroller = IComptroller(addressCompComptroller);
        globalPauseOperation = IGlobalPauseOperation(addressPauseOperation);
        tokenComp = IERC20Upgradeable(addressComp);
        __BaseUpgradeablePausable_init(_msgSender());
    }

    /// @notice one time function to initialize the contract and set protocolID
    /// @dev do ensure addCoveredProtocol() function has been called in 
    /// SmartContract ZP Controller contract before calling out this function
    /// controllerAddress: Zero Premium Controller contract address
    /// protocolName: Name of the protocol
    /// deployedAddress: deployment address of this contract
    /// protocolID_: unique protocol ID generated in Zero Premium Controller contract
    function init( 
        address controllerAddress,
        string memory protocolName,
        address deployedAddress,
        uint256 protocolID_
    ) external onlyAdmin {
        if (initVersion > 0) {
            revert Compound_ZP__ImmutableChangesError();
        }
        ++initVersion;
        zpController = ISmartContractZPController(controllerAddress);
        (string memory _protocolName, address _protocolAddress) = zpController.getProtocolInfo(protocolID_);
        if (_protocolAddress != deployedAddress) {
            revert Compound_ZP__WrongInfoEnteredError();
        }
        if(keccak256(abi.encodePacked(_protocolName)) != keccak256(abi.encodePacked(protocolName))) {
            revert Compound_ZP__WrongInfoEnteredError();
        }
        protocolID = protocolID_;
    }

    /// @notice this function aims to liquidate user's portfolio balance to compensate affected users
    /// tokenAddresses: token addresses supported on the Compound protocol
    /// cTokenAddresses: respective cToken addresses against the token addresses
    /// claimSettlementAddress: claim settlement address
    /// protocolRiskCategory: risk pool category to be liquidated
    /// liquidationPercent: liquidation percentage, i.e. (100 - liquidation percent)
    function liquidateTokens(
        address[] memory tokenAddresses,
        address[] memory cTokenAddresses,
        address claimSettlementAddress,
        uint256 protocolRiskCategory,
        uint256 liquidatedEpoch
    ) external onlyAdmin {
        uint256 tokenCount = cTokenAddresses.length;
        uint256 liquidationPercent = zpController.getLiquidationFactor(liquidatedEpoch);
        for(uint256 i = 0; i < tokenCount;) {
            if(zpController.getProtocolRiskCategory(protocolID) == protocolRiskCategory) {
                IERC20Upgradeable token = IERC20Upgradeable(tokenAddresses[i]);
                address cTokenAddress = cTokenAddresses[i];
                uint256 previousTokenEpoch = previousChildEpoch[cTokenAddress];
                uint256 vTokenLatestBalance = epochsInfo[cTokenAddress][previousTokenEpoch].cTokenBalance;
                uint256 liquidatedAmount = (
                    (liquidationPercent * vTokenLatestBalance) / 100
                );
                uint256 earnedXVS = _claimRewardCOMP(cTokenAddress);
                epochsInfo[cTokenAddress][childEpoch].rewardDistributionAmount = earnedXVS;
                epochsInfo[cTokenAddress][childEpoch + 1].cTokenBalance = vTokenLatestBalance - liquidatedAmount;
                uint256 amountLiquidated = _liquidateInternal(token, cTokenAddress, liquidatedAmount);
                token.safeTransfer(claimSettlementAddress, amountLiquidated);
                previousChildEpoch[cTokenAddress] = childEpoch + 1;
            }
            ++i;
        }
        _incrementChildEpoch();
    }

    /// @notice this function facilitate users' supply token to Compound Smart Contract
    /// @param tokenAddress: ERC20 token address
    /// @param cTokenAddress: ERC20 cToken address
    /// @param amount: amount of the tokens user wishes to supply
    /// @param deadline: ERC20 token permit deadline
    /// @param permitV: ERC20 token permit signature (value v)
    /// @param permitR: ERC20 token permit signature (value r)
    /// @param permitS: ERC20 token permit signature (value s)
    function supplyToken(
        address tokenAddress, 
        address cTokenAddress, 
        uint256 amount,
        uint256 deadline, 
        uint8 permitV, 
        bytes32 permitR, 
        bytes32 permitS
    ) external override nonReentrant returns(bool) {
        if (amount < 1e10) {
            revert Compound_ZP__LowSupplyAmountError();
        }
        _incrementChildEpoch();

        IERC20Upgradeable token = IERC20Upgradeable(tokenAddress);
        IERC20Upgradeable cToken = IERC20Upgradeable(cTokenAddress);
        IERC20PermitUpgradeable tokenWithPermit = IERC20PermitUpgradeable(tokenAddress);

        if (!usersInfo[_msgSender()][cTokenAddress].isActiveInvested) {
            usersInfo[_msgSender()][cTokenAddress].startChildEpoch = childEpoch;
            usersInfo[_msgSender()][cTokenAddress].isActiveInvested = true;
        }
        uint256 balanceBeforeSupply = cToken.balanceOf(address(this));
        tokenWithPermit.safePermit(_msgSender(), address(this), amount, deadline, permitV, permitR, permitS);
        token.safeTransferFrom(_msgSender(), address(this), amount);
        token.safeIncreaseAllowance(cTokenAddress, amount);
        
        uint mintResult = ICErc20(cTokenAddress).mint(amount);
        if (mintResult != 0){
            revert Compound_ZP__TransactionFailedError();
        }
        uint256 balanceAfterSupply = cToken.balanceOf(address(this));
        _supplyTokenInternal(cTokenAddress, balanceAfterSupply, balanceBeforeSupply);
        emit SuppliedToken(_msgSender(), tokenAddress, amount);
        return true;
    }

    /// @notice this function facilitate users' token withdrawal from contract
    /// tokenAddress: ERC20 token address
    /// cTokenAddress: ERC20 cToken address
    /// amount: cToken balance user wishes to withdraw
    function withdrawToken(
        address tokenAddress, 
        address cTokenAddress, 
        uint256 amount
    ) external override nonReentrant returns(bool) {
        ++childEpoch;
        (uint256 userBalance, uint256 userRewardBalance) = calculateUserBalance(cTokenAddress);

        if(userBalance < amount) {
            revert Compound_ZP__LowAmountError();
        }
        uint256 previousTokenEpoch = previousChildEpoch[cTokenAddress];
        epochsInfo[cTokenAddress][childEpoch].cTokenBalance = (
            epochsInfo[cTokenAddress][previousTokenEpoch].cTokenBalance - amount
        );

        uint256 earnedXVS = _claimRewardCOMP(cTokenAddress);
        epochsInfo[cTokenAddress][childEpoch - 1].rewardDistributionAmount = earnedXVS;

        uint256 userPreviousEpoch = usersInfo[_msgSender()][cTokenAddress].previousChildEpoch;
        userChildEpochBalance[_msgSender()][cTokenAddress][childEpoch] = (
            userChildEpochBalance[_msgSender()][cTokenAddress][userPreviousEpoch] - amount
        );
        if (amount == userBalance) {
            usersInfo[_msgSender()][cTokenAddress].isActiveInvested = false;
        }

        usersInfo[_msgSender()][cTokenAddress].rewardWithdrawn += userRewardBalance;
        _withdrawInternal(tokenAddress, cTokenAddress, amount);
        tokenComp.safeTransfer(_msgSender(), userRewardBalance);
        return true;
    }

    /// @notice this function aims to increment the child epoch & is called during each user write call
    function _incrementChildEpoch() private {
        ++childEpoch;
        uint256 currParentVersion =  zpController.latestVersion();
        parentEpoch[childEpoch] = currParentVersion;
    }

    /// @notice this function aims to claim the reward accrued during the specific epoch
    /// cTokenAddress: cToken address
    function _claimRewardCOMP(address cTokenAddress) private returns(uint256) {
        ICErc20[] memory vTokens = new ICErc20[](1);
        vTokens[0] = ICErc20(cTokenAddress);
        uint256 balanceBeforeClaim = tokenComp.balanceOf(address(this));
        compoundComptroller.claimVenus(address(this), vTokens);
        uint256 balanceAfterClaim = tokenComp.balanceOf(address(this));
        uint256 earnedXVS = balanceAfterClaim - balanceBeforeClaim;
        return earnedXVS;
    }

    /// @notice internal liquidate function, to avoid deep stack issue and having modular codebase
    /// token: ERC20 token interface
    /// cTokenAddress: ERC20 cToken Address
    /// liquidatedAmount: amount to be liquidated
    function _liquidateInternal(
        IERC20Upgradeable token, 
        address cTokenAddress,
        uint256 liquidatedAmount
    ) private returns(uint256) {
        ICErc20 cToken = ICErc20(cTokenAddress);
        uint256 balanceBeforeLiquidation = token.balanceOf(address(this));
        uint256 redeemResult = cToken.redeem(liquidatedAmount);
        if (redeemResult != 0){
            revert Compound_ZP__TransactionFailedError();
        }
        uint256 balanceAfterLiquidation = token.balanceOf(address(this));
        uint256 amountLiquidated = balanceAfterLiquidation - balanceBeforeLiquidation;
        return amountLiquidated;
    }

    /// @notice internal supplyToken function, to avoid deep stack issue and having modular codebase
    /// cTokenAddress: cToken address
    /// balanceAfterSupply: cToken contract balance after token supplied
    /// balanceBeforeSupply: cToken contract balance before token supplied
    function _supplyTokenInternal(
        address cTokenAddress, 
        uint256 balanceAfterSupply,
        uint256 balanceBeforeSupply
    ) private {
        uint256 vTokenIssued = (balanceAfterSupply - balanceBeforeSupply);
        uint256 previousTokenEpoch = previousChildEpoch[cTokenAddress];
        uint256 userPreviousEpoch = usersInfo[_msgSender()][cTokenAddress].previousChildEpoch;
        uint256 earnedXVS = _claimRewardCOMP(cTokenAddress);
        epochsInfo[cTokenAddress][childEpoch].cTokenBalance = (
            epochsInfo[cTokenAddress][previousTokenEpoch].cTokenBalance + vTokenIssued
        );
        epochsInfo[cTokenAddress][childEpoch - 1].rewardDistributionAmount = earnedXVS;
        userChildEpochBalance[_msgSender()][cTokenAddress][childEpoch] = (
            userChildEpochBalance[_msgSender()][cTokenAddress][userPreviousEpoch] + vTokenIssued
        );
        previousChildEpoch[cTokenAddress] = childEpoch;
    }

    /// @notice internal withdraw function, to avoid deep stack issue and having modular codebase
    /// tokenAddress: token address
    /// cTokenAddress: cToken address
    /// amount: cToken amount user wishes to withdraw
    function _withdrawInternal(
        address tokenAddress,
        address cTokenAddress,
        uint256 amount
    ) private {
        IERC20Upgradeable token = IERC20Upgradeable(tokenAddress);
        ICErc20 cToken = ICErc20(cTokenAddress);      
        uint256 balanceBeforeRedeem = token.balanceOf(address(this));
        uint256 redeemResult = cToken.redeem(amount);
        if (redeemResult != 0){
            revert Compound_ZP__TransactionFailedError();
        }
        uint256 balanceAfterRedeem = token.balanceOf(address(this));
        uint256 amountToBePaid = (balanceAfterRedeem - balanceBeforeRedeem);
        previousChildEpoch[cTokenAddress] = childEpoch;
        token.safeTransfer(_msgSender(), amountToBePaid);  
    }

    /// @notice this function aims to provide user cToken balance in real-time after any liquidations, if happened
    /// cTokenAddress: cToken address
    function calculateUserBalance(
        address cTokenAddress
    ) public view override returns(uint256, uint256) {
        uint256 userBalance = 0;
        uint256 userRewardBalance = 0;
        uint256 userStartVersion = usersInfo[_msgSender()][cTokenAddress].startChildEpoch;
        uint256 currVersion = childEpoch;
        uint256 riskPoolCategory = 0;
        uint256 parentVersion = 0;
        for(uint i = userStartVersion; i < currVersion;) {
            userBalance = (
                userChildEpochBalance[_msgSender()][cTokenAddress][i] > 0 ? 
                userChildEpochBalance[_msgSender()][cTokenAddress][i] : userBalance
            );
            uint256 rewardEarned = (
                (userBalance * epochsInfo[cTokenAddress][i].rewardDistributionAmount) / 
                epochsInfo[cTokenAddress][i].cTokenBalance
            );
            userRewardBalance += rewardEarned;
            uint256 _parentVersion = parentEpoch[i];
            /// this check ensures that if liquidation has happened on a particular parent version,
            /// then user needs to liquidated once, not again and again for each child version loop call.
            if(parentVersion != _parentVersion) {
                parentVersion = _parentVersion;
                if (zpController.ifProtocolUpdated(protocolID, parentVersion)) {
                    riskPoolCategory = zpController.getProtocolRiskCategory(protocolID, parentVersion);
                }
                if (zpController.isRiskPoolLiquidated(parentVersion, riskPoolCategory)) {
                    userBalance = ((userBalance * zpController.getLiquidationFactor(parentVersion)) / 100);
                }
            }
            ++i; 
        }
        userRewardBalance -= usersInfo[_msgSender()][cTokenAddress].rewardWithdrawn;
        return (userBalance, userRewardBalance);
    }
}