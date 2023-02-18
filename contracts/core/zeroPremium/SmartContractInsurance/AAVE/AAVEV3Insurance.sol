// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/// @title AAVE Zero Premium Insurance Contract
/// @author Anshik Bansal <anshik@safezen.finance>

/// Importing required interfaces
import "./../../../../interfaces/IGlobalPauseOperation.sol";
import "./../../../../interfaces/AAVE/IAAVEV3Interface.sol";
import "./../../../../interfaces/AAVE/IAAVEV3Incentives.sol";
import "./../../../../interfaces/AAVE/IAAVEImplementation.sol"; 
import "./../../../../interfaces/ISmartContractZPController.sol"; 

/// Importing required libraries
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

/// Importing required contracts
import "./../../../../BaseUpgradeablePausable.sol";

/// Report any bug or issues at:
/// @custom:security-contact anshik@safezen.finance
contract AAVEV3Insurance is IAAVEImplementation, BaseUpgradeablePausable {
    
    // ::::::::::::::::: STATE VARIABLES AND DECLARATIONS :::::::::::::::: //
    
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeERC20Upgradeable for IERC20PermitUpgradeable;

    /// protocolID: unique protocol ID
    /// childEpoch: time interval between any new activity recorded, i.e. supply, withdraw or liquidate
    /// initVersion: counter to initialize the init one-time function, max value can be 1.
    /// PLATFORM_FEE: platform fee on the profit earned
    /// rewardTokenAdddresses: AAVE reward token addresses
    uint256 public protocolID;
    uint256 public childEpoch;
    uint256 public initVersion;
    uint256 public constant PLATFORM_FEE = 90;
    address[] public rewardTokenAddresses;

    /// interfaceAAVEV3: AAVE V3 contract interface
    /// incentivesAAVEV3: AAVE V3 Incentives contract interface
    /// zpController: Zero Premium contract interface
    /// globalPauseOperation: Global Pause Operation contract interface 
    IAAVEV3Interface public interfaceAAVEV3;
    IAAVEV3Incentives public incentivesAAVEV3;
    ISmartContractZPController public zpController;
    IGlobalPauseOperation public globalPauseOperation;

    /// @notice stores important user-related info
    /// isActiveInvested: checks if the user is actively invested or not
    /// rewardWithdrawn: amount of reward token user has withdrawn
    /// startChildEpoch: epoch number when user first interacted with the contract
    /// previousChildEpoch: user's last contract interaction epoch id
    /// lastRewardWithdrawalEpoch: user's last reward withdrawal epoch id
    struct UserInfo {
        bool isActiveInvested;
        uint256 startChildEpoch;
        uint256 previousChildEpoch;
        uint256 lastRewardWithdrawalEpoch;
    }

    /// @notice stores information related to the specific epoch number
    /// aTokenBalance: "cumulative" aToken balance
    /// rewardDistributionAmount: reward amount collected for the specific epoch 
    struct EpochSpecificInfo {
        uint256 aTokenBalance;
        mapping(address => uint256) rewardDistributionAmount;
    }

    /// @notice mapping: uint256 childEpoch => uint256 zeroPremiumControllerEpoch
    mapping(uint256 => uint256) private parentEpoch;

    /// @notice mapping: address rewardTokenAddress => bool isExist
    mapping(address => bool) public rewardTokenExists;

    /// @notice mapping: address aTokenAddress => uint256 previousChildEpoch
    mapping(address => uint256) private previousChildEpoch;
    
    /// @notice mapping: address userAddress => address aTokenAddress => struct UserInfo
    mapping(address => mapping(address => UserInfo)) private usersInfo;
    
    /// @notice mapping: address aTokenAddress => uint256 childEpoch => struct EpochSpecificInfo
    mapping(address => mapping(uint256 => EpochSpecificInfo)) private epochsInfo;
    
    /// @notice mapping: address userAddress => address aTokenAddress => \
    /// \ uint256 childEpoch => uint256 cTokenUserBalance
    mapping(address => mapping(address => mapping(uint256 => uint256))) private userChildEpochBalance;

    // :::::::::::::::::::::::: WRITING FUNCTIONS :::::::::::::::::::::::: //

    // ::::::::::::::::::::::::: ADMIN FUNCTIONS ::::::::::::::::::::::::: //

    /// @notice initialize function, called during the contract initialization
    /// @param addressPauseOperation: Global Pause Operation contract address
    function initialize(
        address addressPauseOperation
    ) external initializer {
        globalPauseOperation = IGlobalPauseOperation(addressPauseOperation);
        __BaseUpgradeablePausable_init(_msgSender());
    }

    /// @notice one time function to initialize the contract and set protocolID
    /// @dev do ensure addCoveredProtocol() function has been called in \
    /// \ SmartContract ZP Controller contract before calling out this function
    /// @param protocolID_: unique protocol ID generated in Zero Premium Controller contract
    /// @param lendingAddress: AAVE V3 lending address
    /// @param deployedAddress: deployment address of this contract
    /// @param zpControllerAddress: Zero Premium Controller contract address
    /// @param protocolName: Name of the protocol
    function init( 
        uint256 protocolID_,
        address lendingAddress,
        address deployedAddress,
        address zpControllerAddress,
        string memory protocolName
    ) external onlyAdmin {
        if (initVersion > 0) {
            revert AAVE_ZP__InitializedEarlierError();
        }
        ++initVersion;
        interfaceAAVEV3 = IAAVEV3Interface(lendingAddress);
        zpController = ISmartContractZPController(zpControllerAddress);
        (string memory _protocolName, address _protocolAddress) = zpController.getProtocolInfo(protocolID_);
        if (_protocolAddress != deployedAddress) {
            revert AAVE_ZP__WrongInfoEnteredError();
        }
        if(keccak256(abi.encodePacked(_protocolName)) != keccak256(abi.encodePacked(protocolName))) {
            revert AAVE_ZP__WrongInfoEnteredError();
        }
        protocolID = protocolID_;
    }

    /// @notice this function aims to liquidate user's portfolio balance to compensate affected users
    /// @param tokenAddresses: token addresses supported on the AAVE protocol
    /// @param aTokenAddresses: respective aToken addresses against the token addresses
    /// @param claimSettlementAddress: claim settlement address
    /// @param protocolRiskCategory: risk pool category to be liquidated
    /// @param liquidatedEpoch: parent zpController epoch ID
    function liquidateTokens(
        address[] memory tokenAddresses,
        address[] memory aTokenAddresses,
        address claimSettlementAddress,
        uint256 protocolRiskCategory,
        uint256 liquidatedEpoch
    ) external onlyAdmin {
        if(tokenAddresses.length != aTokenAddresses.length) {
            revert AAVE_ZP__IncorrectAddressesInputError();
        }
        uint256 tokenCount = tokenAddresses.length;
        uint256 liquidationPercent = zpController.getLiquidationFactor(liquidatedEpoch);
        for(uint256 i = 0; i < tokenCount;) {
            if(zpController.getProtocolRiskCategory(protocolID) == protocolRiskCategory) {
                IERC20Upgradeable token = IERC20Upgradeable(tokenAddresses[i]);
                address aTokenAddress = aTokenAddresses[i];
                uint256 previousTokenEpoch = previousChildEpoch[aTokenAddress];
                uint256 aTokenLatestBalance = epochsInfo[aTokenAddress][previousTokenEpoch].aTokenBalance;
                uint256 liquidatedAmount = (
                    (liquidationPercent * aTokenLatestBalance) / 100
                );
                epochsInfo[aTokenAddress][childEpoch + 1].aTokenBalance = aTokenLatestBalance - liquidatedAmount;
                uint256 amountLiquidated = _liquidateInternal(token, aTokenAddress, liquidatedAmount);
                previousChildEpoch[aTokenAddress] = childEpoch + 1;
                /// as the below operation call is in loop, violating C-E-I pattern, \
                /// \ the function returns call status,and if false, reverts the operation.
                bool claimSuccess = _claimRewards(aTokenAddress, childEpoch);
                if(!claimSuccess) {
                    revert AAVE_ZP__RewardClaimOperationReverted();
                }
                token.safeTransfer(claimSettlementAddress, amountLiquidated);
            }
            ++i;
        }
        _incrementChildEpoch();
    }
        
    // :::::::::::::::::::::::: EXTERNAL FUNCTIONS ::::::::::::::::::::::: //

    /// @notice this function facilitate users' supply token to AAVE Smart Contract
    /// @param tokenAddress: ERC20 token address
    /// @param aTokenAddress: ERC20 aToken address
    /// @param amount: amount of the tokens user wishes to supply
    /// @param deadline: ERC20 token permit deadline
    /// @param permitV: ERC20 token permit signature (value v)
    /// @param permitR: ERC20 token permit signature (value r)
    /// @param permitS: ERC20 token permit signature (value s)
    function supplyToken(
        address tokenAddress, 
        address aTokenAddress, 
        uint256 amount,
        uint256 deadline, 
        uint8 permitV, 
        bytes32 permitR, 
        bytes32 permitS
    ) external override nonReentrant returns(bool) {
        ifNotPaused();
        if (amount < 1e10) {
            revert AAVE_ZP__LessThanMinimumAmountError();
        }
        _incrementChildEpoch();

        IERC20Upgradeable token = IERC20Upgradeable(tokenAddress);
        IERC20Upgradeable aToken = IERC20Upgradeable(aTokenAddress);
        IERC20PermitUpgradeable tokenWithPermit = IERC20PermitUpgradeable(tokenAddress);

        if (!usersInfo[_msgSender()][aTokenAddress].isActiveInvested) {
            usersInfo[_msgSender()][aTokenAddress].startChildEpoch = childEpoch;
            usersInfo[_msgSender()][aTokenAddress].lastRewardWithdrawalEpoch = childEpoch;
            usersInfo[_msgSender()][aTokenAddress].isActiveInvested = true;
        }
        uint256 balanceBeforeSupply = aToken.balanceOf(address(this));
        tokenWithPermit.safePermit(_msgSender(), address(this), amount, deadline, permitV, permitR, permitS);
        token.safeTransferFrom(_msgSender(), address(this), amount);
        token.safeIncreaseAllowance(address(interfaceAAVEV3), amount);
        
        interfaceAAVEV3.supply(tokenAddress, amount, address(this), 0);
        
        uint256 balanceAfterSupply = aToken.balanceOf(address(this));
        bool claimSuccess = _claimRewards(aTokenAddress, (childEpoch - 1));
        if(!claimSuccess) {
            revert AAVE_ZP__RewardClaimOperationReverted();
        }
        /// as the below operation call is made after token transfer, violating C-E-I pattern, \
        /// \ the function returns call status,and if false, reverts the operation.
        bool success = _supplyTokenInternal(_msgSender(), aTokenAddress, balanceBeforeSupply, balanceAfterSupply);
        if(!success) {
            revert AAVE_ZP__TokenSupplyOperationReverted();
        }
        emit SuppliedToken(_msgSender(), tokenAddress, amount);
        return true;
    }

    /// @notice this function facilitate users' token withdrawal from contract
    /// @param tokenAddress: ERC20 token address
    /// @param aTokenAddress: ERC20 aToken address
    /// @param amount: aToken balance user wishes to withdraw
    function withdrawToken(
        address tokenAddress, 
        address aTokenAddress, 
        uint256 amount
    ) external override nonReentrant returns(bool) {
        uint256 initialBalanceCheck = calculateUserBalance(_msgSender(), aTokenAddress);
        if(initialBalanceCheck < amount) {
            revert AAVE_ZP__LessThanMinimumAmountError();
        }
        ifNotPaused();
        _incrementChildEpoch();
        bool claimSuccess = _claimRewards(aTokenAddress, (childEpoch - 1));
        if(!claimSuccess) {
            revert AAVE_ZP__RewardClaimOperationReverted();
        }
        (uint256 userBalance, uint256[] memory userRewardBalance) = calculateUserRewardAndBalance(_msgSender(), aTokenAddress);

        uint256 previousTokenEpoch = previousChildEpoch[aTokenAddress];
        epochsInfo[aTokenAddress][childEpoch].aTokenBalance = (
            epochsInfo[aTokenAddress][previousTokenEpoch].aTokenBalance - amount
        );
        
        uint256 userPreviousEpoch = usersInfo[_msgSender()][aTokenAddress].previousChildEpoch;
        userChildEpochBalance[_msgSender()][aTokenAddress][childEpoch] = (
            userChildEpochBalance[_msgSender()][aTokenAddress][userPreviousEpoch] - amount
        );
        if (amount == userBalance) {
            usersInfo[_msgSender()][aTokenAddress].isActiveInvested = false;
        }

        
        bool success = _withdrawInternal(_msgSender(), tokenAddress, aTokenAddress, amount);
        if (!success) {
            revert AAVE_ZP__TokenWithdrawalOperationReverted();
        }
        
        for(uint256 i = 0; i < rewardTokenAddresses.length;) {
            address rewardTokenAddress = rewardTokenAddresses[i];
            if(userRewardBalance[i] > 0) {
                IERC20Upgradeable(rewardTokenAddress).transfer(_msgSender(), userRewardBalance[i]);
            }
            ++i;
        }
        return true;
    }

    // :::::::::::::::::::::::: PRIVATE FUNCTIONS :::::::::::::::::::::::: //

    function _addRewardToken(address addressRewardToken) private {
        if(!rewardTokenExists[addressRewardToken]) {
            rewardTokenExists[addressRewardToken] = true;
            rewardTokenAddresses.push(addressRewardToken);
        }
    }

    /// @notice this function aims to increment the child epoch & is called during each user write call
    function _incrementChildEpoch() private {
        ++childEpoch;
        uint256 currParentVersion =  zpController.latestVersion();
        parentEpoch[childEpoch] = currParentVersion;
    }

    /// @notice this function aims to claim the reward accrued during the specific epoch
    /// aTokenAddress: aToken address
    function _claimRewards(
        address aTokenAddress,
        uint256 childEpoch_
    ) private returns(bool) {
        address[] memory aTokens = new address[](1);
        aTokens[0] = aTokenAddress;
        (address[] memory rewardDistributionList, uint256[] memory rewardDistributionAmount) = incentivesAAVEV3.claimAllRewardsToSelf(aTokens);
        
        EpochSpecificInfo storage epochInfo = epochsInfo[aTokenAddress][childEpoch_];
        for(uint256 i= 0; i < rewardDistributionList.length;) {
            address addressRewardToken = rewardDistributionList[i];
            _addRewardToken(addressRewardToken);
            epochInfo.rewardDistributionAmount[addressRewardToken] = rewardDistributionAmount[i];
            ++i;
        }
        return true;
    }

    /// @notice internal liquidate function, to avoid deep stack issue and having modular codebase
    /// token: ERC20 token interface
    /// aTokenAddress: ERC20 aToken Address
    /// liquidatedAmount: amount to be liquidated
    function _liquidateInternal(
        IERC20Upgradeable token, 
        address aTokenAddress,
        uint256 liquidatedAmount
    ) private returns(uint256) {
        uint256 balanceBeforeLiquidation = token.balanceOf(address(this));
        
        interfaceAAVEV3.withdraw(aTokenAddress, liquidatedAmount, address(this));
        
        uint256 balanceAfterLiquidation = token.balanceOf(address(this));
        uint256 amountLiquidated = balanceAfterLiquidation - balanceBeforeLiquidation;
        return amountLiquidated;
    }

    /// @notice internal supplyToken function, to avoid deep stack issue and having modular codebase
    /// aTokenAddress: aToken address
    /// balanceAfterSupply: aToken contract balance after token supplied
    /// balanceBeforeSupply: aToken contract balance before token supplied
    function _supplyTokenInternal(
        address addressUser,
        address aTokenAddress, 
        uint256 balanceBeforeSupply,
        uint256 balanceAfterSupply
    ) private returns(bool) {
        uint256 aTokenIssued = (balanceAfterSupply - balanceBeforeSupply);
        uint256 previousTokenEpoch = previousChildEpoch[aTokenAddress];
        uint256 userPreviousEpoch = usersInfo[addressUser][aTokenAddress].previousChildEpoch;
        epochsInfo[aTokenAddress][childEpoch].aTokenBalance = (
            epochsInfo[aTokenAddress][previousTokenEpoch].aTokenBalance + aTokenIssued
        );
        userChildEpochBalance[addressUser][aTokenAddress][childEpoch] = (
            userChildEpochBalance[addressUser][aTokenAddress][userPreviousEpoch] + aTokenIssued
        );
        previousChildEpoch[aTokenAddress] = childEpoch;
        usersInfo[addressUser][aTokenAddress].previousChildEpoch = childEpoch;
        return true;
    }

    /// @notice internal withdraw function, to avoid deep stack issue and having modular codebase
    /// tokenAddress: token address
    /// aTokenAddress: aToken address
    /// amount: aToken amount user wishes to withdraw
    function _withdrawInternal(
        address addressUser,
        address tokenAddress,
        address aTokenAddress,
        uint256 amount
    ) private returns(bool) {
        IERC20Upgradeable token = IERC20Upgradeable(tokenAddress);  
        uint256 balanceBeforeRedeem = token.balanceOf(address(this));

        interfaceAAVEV3.withdraw(aTokenAddress, amount, address(this));
        
        uint256 balanceAfterRedeem = token.balanceOf(address(this));
        uint256 amountToBePaid = (balanceAfterRedeem - balanceBeforeRedeem);
        previousChildEpoch[aTokenAddress] = childEpoch;
        usersInfo[addressUser][aTokenAddress].previousChildEpoch = childEpoch;
        usersInfo[addressUser][aTokenAddress].lastRewardWithdrawalEpoch = childEpoch;
        token.safeTransfer(addressUser, amountToBePaid);  
        return true;
    }

    // :::::::::::::::::::::::: READING FUNCTIONS :::::::::::::::::::::::: //
    
    // ::::::::::::::::::: PUBLIC PURE/VIEW FUNCTIONS :::::::::::::::::::: //
    
    /// @dev this function checks if the contracts' certain function calls has to be paused temporarily
    function ifNotPaused() public view {
        if((paused()) || (globalPauseOperation.isPaused())) {
            revert AAVE_ZP__OperationPaused();
        } 
    }

    function calculateUserBalance(
        address addressUser,
        address aTokenAddress
    ) public view returns(uint256) {
        uint256 userBalance = 0;
        uint256 parentVersion = 0;
        uint256 riskPoolCategory = 0;        
        uint256 currVersion = childEpoch;
        uint256 userStartVersion = usersInfo[addressUser][aTokenAddress].startChildEpoch;
        
        for(uint i = userStartVersion; i < currVersion;) {
            userBalance = (
                userChildEpochBalance[addressUser][aTokenAddress][i] > 0 ? 
                userChildEpochBalance[addressUser][aTokenAddress][i] : userBalance
            );

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
        return userBalance;
    }

    /// @notice this function aims to provide user aToken balance in real-time after any liquidations, if happened
    /// aTokenAddress: aToken address
    function calculateUserRewardAndBalance(
        address addressUser,
        address aTokenAddress
    ) public view returns(uint256, uint256[] memory) {
        uint256 userBalance = 0;
        uint256 parentVersion = 0;
        uint256 riskPoolCategory = 0;        
        uint256 currVersion = childEpoch;
        uint256 userStartVersion = usersInfo[addressUser][aTokenAddress].startChildEpoch;
        
        uint256[] memory userRewardTokensAmount = new uint256[](rewardTokenAddresses.length);
        
        for(uint i = userStartVersion; i < currVersion;) {
            userBalance = (
                userChildEpochBalance[addressUser][aTokenAddress][i] > 0 ? 
                userChildEpochBalance[addressUser][aTokenAddress][i] : userBalance
            );

            if(usersInfo[addressUser][aTokenAddress].lastRewardWithdrawalEpoch < i) {
                for(uint256 j = 0; j < rewardTokenAddresses.length;) {
                    address rewardToken = rewardTokenAddresses[j];
                    EpochSpecificInfo storage epochRewardInfo = epochsInfo[aTokenAddress][i];
                    userRewardTokensAmount[j] += (
                        (userBalance * epochRewardInfo.rewardDistributionAmount[rewardToken]) / epochsInfo[aTokenAddress][i].aTokenBalance
                    );
                    ++j;
                }
            }

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
        return (userBalance, userRewardTokensAmount);
    }

    // ::::::::::::::::::::::::: END OF CONTRACT ::::::::::::::::::::::::: //

}