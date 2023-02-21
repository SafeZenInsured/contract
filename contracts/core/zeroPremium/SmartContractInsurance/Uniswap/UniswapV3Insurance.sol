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
import "./../../../../interfaces/AAVE/DataTypes.sol";

/// Importing required contracts
import "./../../../../BaseUpgradeablePausable.sol";

/// Report any bug or issues at:
/// @custom:security-contact anshik@safezen.finance
/// Compound: (((((SupplyRate / 1e18) * 7200ETH Blocks per yr) + 1) ** 365) - 1) * 100
/// (User Balance * Compound * Platform Fee) / 1e2 = platformFee 
contract UniswapV3Insurance is IAAVEImplementation, BaseUpgradeablePausable {
    
    // ::::::::::::::::: STATE VARIABLES AND DECLARATIONS :::::::::::::::: //
    
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeERC20Upgradeable for IERC20PermitUpgradeable;

    /// protocolID: unique protocol ID
    /// childEpoch: time interval between any new activity recorded, i.e. supply, withdraw or liquidate
    /// initVersion: counter to initialize the init one-time function, max value can be 1.
    /// PLATFORM_FEE: platform fee on the profit aka yields earned
    /// rewardTokenAdddresses: AAVE reward token addresses
    uint256 public protocolID;
    uint256 public childEpoch;
    uint256 public initVersion;
    uint256 public constant PLATFORM_FEE = 10;
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
        uint256 poolSupplyRate;
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
    mapping(uint256 => uint256) public parentEpoch;

    /// @notice mapping: address rewardTokenAddress => bool isExist
    mapping(address => bool) public rewardTokenExists;

    /// @notice mapping: address aTokenAddress => uint256 previousChildEpoch
    mapping(address => uint256) public previousChildEpoch;
    
    /// @notice mapping: address userAddress => address aTokenAddress => struct UserInfo
    mapping(address => mapping(address => UserInfo)) public usersInfo;
    
    /// @notice mapping: address aTokenAddress => uint256 childEpoch => struct EpochSpecificInfo
    mapping(address => mapping(uint256 => EpochSpecificInfo)) public epochsInfo;
    
    /// @notice mapping: address userAddress => address aTokenAddress => \
    /// \ uint256 childEpoch => uint256 cTokenUserBalance
    mapping(address => mapping(address => mapping(uint256 => uint256))) public userChildEpochBalance;

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
        address incentivesAddress,
        address deployedAddress,
        address zpControllerAddress,
        string memory protocolName
    ) external onlyAdmin {
        if (initVersion > 0) {
            revert AAVE_ZP__InitializedEarlierError();
        }
        ++initVersion;
        interfaceAAVEV3 = IAAVEV3Interface(lendingAddress);
        incentivesAAVEV3 = IAAVEV3Incentives(incentivesAddress);
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
        bool success = _liquidateTokens(tokenAddresses, aTokenAddresses, claimSettlementAddress, protocolRiskCategory, liquidatedEpoch);
        if(!success) {
            revert AAVE_ZP__LiquidateTokensOperationFailedError();
        }
    }

    function _liquidateTokens(
        address[] memory tokenAddresses,
        address[] memory aTokenAddresses,
        address claimSettlementAddress,
        uint256 protocolRiskCategory,
        uint256 liquidatedEpoch
    ) private returns(bool) {
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
                
                uint256 balanceBeforeLiquidation = token.balanceOf(address(this));
                interfaceAAVEV3.withdraw(aTokenAddress, liquidatedAmount, address(this));
                uint256 balanceAfterLiquidation = token.balanceOf(address(this));
                
                uint256 amountLiquidated = balanceAfterLiquidation - balanceBeforeLiquidation;

                _aTokenBalanceUpdate(false, childEpoch + 1, liquidatedAmount, aTokenAddress);
                _claimRewards(aTokenAddress, childEpoch);

                token.safeTransfer(claimSettlementAddress, amountLiquidated);
            }
            ++i;
        }
        _incrementChildEpoch();
        return true;
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
    ) external override nonReentrant {
        ifNotPaused();
        if (amount < 1e10) {
            revert AAVE_ZP__LessThanMinimumAmountError();
        }
        
        bool success = _supplyToken(_msgSender(), tokenAddress, aTokenAddress, amount, deadline, permitV, permitR, permitS);
        if (!success) {
            revert AAVE_ZP__TokenSupplyOperationReverted();
        }
        
        emit SuppliedToken(_msgSender(), tokenAddress, amount);
    }

    
    function _supplyToken(
        address addressUser,
        address tokenAddress, 
        address aTokenAddress, 
        uint256 amount,
        uint256 deadline, 
        uint8 permitV, 
        bytes32 permitR, 
        bytes32 permitS
    ) private returns(bool) {
        _incrementChildEpoch();
        _claimRewards(aTokenAddress, (childEpoch - 1));
        _updateUserInfo(true, tokenAddress, aTokenAddress);

        IERC20Upgradeable token = IERC20Upgradeable(tokenAddress);
        IERC20Upgradeable aToken = IERC20Upgradeable(aTokenAddress);

        IERC20PermitUpgradeable tokenWithPermit = IERC20PermitUpgradeable(tokenAddress);

        uint256 balanceBeforeSupply = aToken.balanceOf(address(this));
        tokenWithPermit.safePermit(addressUser, address(this), amount, deadline, permitV, permitR, permitS);
        token.safeTransferFrom(addressUser, address(this), amount);
        token.safeIncreaseAllowance(address(interfaceAAVEV3), amount);
        interfaceAAVEV3.supply(tokenAddress, amount, address(this), 0);
        uint256 balanceAfterSupply = aToken.balanceOf(address(this));
        _afterSupply(addressUser, aTokenAddress, balanceBeforeSupply, balanceAfterSupply);
        return true;
    }

    function _afterSupply(
        address addressUser,
        address aTokenAddress,
        uint256 balanceBeforeSupply,
        uint256 balanceAfterSupply
    ) private {
        uint256 aTokenIssued = balanceAfterSupply - balanceBeforeSupply;
        _aTokenBalanceUpdate(true, childEpoch, aTokenIssued, aTokenAddress);
        _updateUserBalance(true, aTokenIssued, addressUser, aTokenAddress);


    }

    // function getLiquidityRate(address tokenAddress) public view returns(uint256) {
    //     DataTypes.ReserveData memory reserveData = interfaceAAVEV3.getReserveData(tokenAddress);
    //     return reserveData.currentLiquidityRate;
    // }

    function _aTokenBalanceUpdate(
        bool isSupplied,
        uint256 childEpoch_,
        uint256 amount, 
        address aTokenAddress
    ) private {
        uint256 previousTokenEpoch = previousChildEpoch[aTokenAddress];
        epochsInfo[aTokenAddress][childEpoch_].aTokenBalance = (
            isSupplied ? 
            (epochsInfo[aTokenAddress][previousTokenEpoch].aTokenBalance + amount) : 
            (epochsInfo[aTokenAddress][previousTokenEpoch].aTokenBalance - amount)
        );
        previousChildEpoch[aTokenAddress] = childEpoch_;  
    }

    function _updateUserBalance(
        bool isSupplied,
        uint256 amount,
        address addressUser, 
        address aTokenAddress
    ) private {
        uint256 userPreviousEpoch = usersInfo[addressUser][aTokenAddress].previousChildEpoch;
        userChildEpochBalance[addressUser][aTokenAddress][childEpoch] = (
            isSupplied ? 
            (userChildEpochBalance[addressUser][aTokenAddress][userPreviousEpoch] + amount) : 
            (userChildEpochBalance[addressUser][aTokenAddress][userPreviousEpoch] - amount)
        );
        
        usersInfo[addressUser][aTokenAddress].previousChildEpoch = childEpoch;
    }

    function _updateUserInfo(
        bool isSupplied,
        address tokenAddress, 
        address aTokenAddress
    ) private {
        UserInfo storage userInfo = usersInfo[_msgSender()][aTokenAddress];
        DataTypes.ReserveData memory reserveData = interfaceAAVEV3.getReserveData(tokenAddress);
        if((isSupplied) && (!userInfo.isActiveInvested)) {
            userInfo.isActiveInvested = true;
            userInfo.startChildEpoch = childEpoch;
        }

        userInfo.poolSupplyRate = reserveData.currentLiquidityRate;
        userInfo.lastRewardWithdrawalEpoch = childEpoch;        
    }

    /// @notice this function facilitate users' token withdrawal from contract
    /// @param tokenAddress: ERC20 token address
    /// @param aTokenAddress: ERC20 aToken address
    /// @param amount: aToken balance user wishes to withdraw
    function withdrawToken(
        address tokenAddress, 
        address aTokenAddress, 
        uint256 amount
    ) external override nonReentrant {
        ifNotPaused();
        (uint256 initialBalanceCheck, ) = calculateUserRewardAndBalance(_msgSender(), aTokenAddress);
        if(initialBalanceCheck < amount) {
            revert AAVE_ZP__LessThanMinimumAmountError();
        }

        bool success = _withdraw(_msgSender(), tokenAddress, aTokenAddress, amount);
        if(!success) {
            revert AAVE_ZP__TokenWithdrawalOperationReverted();
        }
    }

    function _withdraw(
        address addressUser,
        address tokenAddress, 
        address aTokenAddress, 
        uint256 amount
    ) private returns(bool) {
        _incrementChildEpoch();
        _claimRewards(aTokenAddress, (childEpoch - 1));
        _aTokenBalanceUpdate(false, childEpoch, amount, aTokenAddress);
        _updateUserInfo(false, tokenAddress, aTokenAddress);
        _updateUserBalance(false, amount, addressUser, aTokenAddress);
        
        (uint256 userBalance, uint256[] memory userRewardBalance) = calculateUserRewardAndBalance(_msgSender(), aTokenAddress);

        if (amount == userBalance) {
            usersInfo[_msgSender()][aTokenAddress].isActiveInvested = false;
        }

        IERC20Upgradeable token = IERC20Upgradeable(tokenAddress);  
        
        uint256 balanceBeforeRedeem = token.balanceOf(address(this));
        interfaceAAVEV3.withdraw(aTokenAddress, amount, address(this));
        uint256 balanceAfterRedeem = token.balanceOf(address(this));
        uint256 amountToBePaid = (balanceAfterRedeem - balanceBeforeRedeem);
        token.safeTransfer(_msgSender(), amountToBePaid);  
        
        for(uint256 i = 0; i < rewardTokenAddresses.length;) {
            address rewardTokenAddress = rewardTokenAddresses[i];
            if(userRewardBalance[i] > 0) {
                IERC20Upgradeable(rewardTokenAddress).safeTransfer(_msgSender(), userRewardBalance[i]);
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
    function _incrementChildEpoch() internal {
        ++childEpoch;
        uint256 currParentVersion =  zpController.latestVersion();
        parentEpoch[childEpoch] = currParentVersion;
    }

    /// @notice this function aims to claim the reward accrued during the specific epoch
    /// aTokenAddress: aToken address
    function _claimRewards(
        address aTokenAddress,
        uint256 childEpoch_
    ) private {
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
    }

    

    
    // :::::::::::::::::::::::: READING FUNCTIONS :::::::::::::::::::::::: //
    
    // ::::::::::::::::::: PUBLIC PURE/VIEW FUNCTIONS :::::::::::::::::::: //
    
    /// @dev this function checks if the contracts' certain function calls has to be paused temporarily
    function ifNotPaused() public view {
        if((paused()) || (globalPauseOperation.isPaused())) {
            revert AAVE_ZP__OperationPaused();
        } 
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
        uint256 liquidatedAmount = 0;        
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
                    liquidatedAmount += (
                        userBalance - (
                            (userBalance * zpController.getLiquidationFactor(parentVersion)) / 100
                        )
                    );
                }
            }
            ++i; 
        }
        userBalance -= liquidatedAmount;
        uint256 poolSupplyRate = usersInfo[addressUser][aTokenAddress].poolSupplyRate;
        /// To get the supply aka liquidity rate in AAVE, one needs to divide the liquidityRate value by 1e27 
        /// to get the liquidity rate in percentage. Furthermore, for precision, we're dividing the pool supply rate as:
        /// yield = (userBalance * (poolSupplyRate / 1e27)) gives us the yield amount.
        /// platformFee = (yield * (PLATFORM_FEE / 100)) gives us the amount of fee that we will charge from user.
        /// therefore: (userBalance * (poolSupplyRate / 1e27) * (PLATFORM_FEE / 1e2)) would get us our platform fee
        /// and, for math precision, the code has been modified as written below:
        uint256 platformFee = ((userBalance * (poolSupplyRate / 1e18) * PLATFORM_FEE) / (1e11));
        userBalance -= platformFee;
        return (userBalance, userRewardTokensAmount);
    }

    // ::::::::::::::::::::::::: END OF CONTRACT ::::::::::::::::::::::::: //

}