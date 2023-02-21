// // SPDX-License-Identifier: BUSL-1.1
// pragma solidity 0.8.16;

// /// @title Venus Zero Premium Insurance Contract
// /// @author Anshik Bansal <anshik@safezen.finance>

// /// Importing required interfaces
// import "./../../../../interfaces/Compound/ICErc20.sol";
// import "./../../../../interfaces/Compound/IComptroller.sol";
// import "./../../../../interfaces/IGlobalPauseOperation.sol";
// import "./../../../../interfaces/ISmartContractZPController.sol";
// import "./../../../../interfaces/Compound/ICompoundImplementation.sol";

// /// Importing required libraries
// import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

// /// Importing required contracts
// import "./../../../../BaseUpgradeablePausable.sol";

// /// Report any bug or issues at:
// /// @custom:security-contact anshik@safezen.finance
// contract VenusInsurance is ICompoundImplementation, BaseUpgradeablePausable {
//     using SafeERC20Upgradeable for IERC20Upgradeable;
//     using SafeERC20Upgradeable for IERC20PermitUpgradeable;

//     uint256 private _protocolID;
//     uint256 private _childEpoch;
//     uint256 private _initVersion;
//     IERC20Upgradeable private _tokenXVS;
//     IComptroller private _venusComptroller;
//     ISmartContractZPController private _zpController;
//     IGlobalPauseOperation private _globalPauseOperation;
    
//     struct UserInfo {
//         bool isActiveInvested;
//         uint256 rewardWithdrawn;
//         uint256 startChildEpoch;
//         uint256 previousChildEpoch;
//     }

//     struct EpochSpecificInfo {
//         uint256 vTokenBalance;
//         uint256 rewardDistributionAmount;
//     }

//     /// Maps ChildVersion => ParentVersion
//     mapping(uint256 => uint256) private parentEpoch;
    
//     /// Maps => User Address => Reward Token Address => UserInfo struct
//     mapping(address => mapping(address => UserInfo)) private usersInfo;
    
//     /// Maps => User Address => Reward Token Address => ChildVersion => UserBalance
//     mapping(address => mapping(address => mapping(uint256 => uint256))) private userChildEpochBalance;

//     /// Maps reward address => Child Version => EpochSpecificInfo
//     mapping(address => mapping(uint256 => EpochSpecificInfo)) private epochsInfo;
    
//     /// Maps Reward token address => Previous Child Epoch
//     mapping(address => uint256) private previousChildEpoch;

//     modifier ifNotPaused() {
//         require(
//             (paused() != true) && 
//             (_globalPauseOperation.isPaused() != true));
//         _;
//     }

//     function initialize(
//         address pauseOperationAddress,
//         address addressXVS
//     ) external initializer {
//         _globalPauseOperation = IGlobalPauseOperation(pauseOperationAddress);
//         _tokenXVS = IERC20Upgradeable(addressXVS);
//         __BaseUpgradeablePausable_init(_msgSender());
//     }

//     function init( 
//         address _controllerAddress,
//         string memory protocolName,
//         address deployedAddress,
//         uint256 protocolID
//     ) external onlyAdmin {
//         if (_initVersion > 0) {
//             revert Compound_ZP__ImmutableChangesError();
//         }
//         ++_initVersion;
//         _zpController = ISmartContractZPController(_controllerAddress);
//         (string memory _protocolName, address _protocolAddress) = _zpController.getProtocolInfo(protocolID);
//         if (_protocolAddress != deployedAddress) {
//             revert Compound_ZP__WrongInfoEnteredError();
//         }
//         if(keccak256(abi.encodePacked(_protocolName)) != keccak256(abi.encodePacked(protocolName))) {
//             revert Compound_ZP__WrongInfoEnteredError();
//         }
//         _protocolID = protocolID;
//     }

//     function liquidateTokens(
//         address[] memory tokenAddresses,
//         address[] memory vTokenAddresses,
//         address claimSettlementAddress,
//         uint256 protocolRiskCategory,
//         uint256 liquidationPercent
//     ) external onlyAdmin {
//         uint256 tokenCount = vTokenAddresses.length;
//         for(uint256 i = 0; i < tokenCount;) {
//             if(_zpController.getProtocolRiskCategory(_protocolID) == protocolRiskCategory) {
//                 IERC20Upgradeable token = IERC20Upgradeable(tokenAddresses[i]);
//                 address vTokenAddress = vTokenAddresses[i];
//                 uint256 previousTokenEpoch = previousChildEpoch[vTokenAddress];
//                 uint256 vTokenLatestBalance = epochsInfo[vTokenAddress][previousTokenEpoch].vTokenBalance;
//                 uint256 liquidatedAmount = (
//                     (liquidationPercent * vTokenLatestBalance) / 100
//                 );
//                 uint256 earnedXVS = claimRewardXVS(vTokenAddress);
//                 epochsInfo[vTokenAddress][_childEpoch].rewardDistributionAmount = earnedXVS;
//                 epochsInfo[vTokenAddress][_childEpoch + 1].vTokenBalance = vTokenLatestBalance - liquidatedAmount;
//                 uint256 amountLiquidated = _liquidateInternal(token, vTokenAddress, liquidatedAmount);
//                 token.safeTransfer(claimSettlementAddress, amountLiquidated);
//                 previousChildEpoch[vTokenAddress] = _childEpoch + 1;
//             }
//             ++i;
//         }
//         _incrementChildEpoch();
//     }

//     function _liquidateInternal(
//         IERC20Upgradeable token, 
//         address vTokenAddress,
//         uint256 liquidatedAmount
//     ) private returns(uint256) {
//         ICErc20 vToken = ICErc20(vTokenAddress);
//         uint256 balanceBeforeLiquidation = token.balanceOf(address(this));
//         uint256 redeemResult = vToken.redeem(liquidatedAmount);
//         if (redeemResult != 0){
//             revert Compound_ZP__TransactionFailedError();
//         }
//         uint256 balanceAfterLiquidation = token.balanceOf(address(this));
//         uint256 amountLiquidated = balanceAfterLiquidation - balanceBeforeLiquidation;
//         return amountLiquidated;
//     }

//     function _incrementChildEpoch() private {
//         ++_childEpoch;
//         uint256 currParentVersion =  _zpController.latestVersion();
//         parentEpoch[_childEpoch] = currParentVersion;
//     }

//     function supplyToken(
//         address tokenAddress, 
//         address vTokenAddress, 
//         uint256 amount,
//         uint256 deadline, 
//         uint8 v, 
//         bytes32 r, 
//         bytes32 s
//     ) external override nonReentrant returns(bool) {
//         if (amount < 1e10) {
//             revert Compound_ZP__LowSupplyAmountError();
//         }
//         _incrementChildEpoch();

//         IERC20Upgradeable token = IERC20Upgradeable(tokenAddress);
//         IERC20Upgradeable vToken = IERC20Upgradeable(vTokenAddress);
//         IERC20PermitUpgradeable tokenWithPermit = IERC20PermitUpgradeable(tokenAddress);

//         if (!usersInfo[_msgSender()][vTokenAddress].isActiveInvested) {
//             usersInfo[_msgSender()][vTokenAddress].startChildEpoch = _childEpoch;
//             usersInfo[_msgSender()][vTokenAddress].isActiveInvested = true;
//         }
//         uint256 balanceBeforeSupply = vToken.balanceOf(address(this));
//         tokenWithPermit.safePermit(_msgSender(), address(this), amount, deadline, v, r, s);
//         token.safeTransferFrom(_msgSender(), address(this), amount);
//         token.safeIncreaseAllowance(vTokenAddress, amount);
        
//         uint mintResult = ICErc20(vTokenAddress).mint(amount);
//         if (mintResult != 0){
//             revert Compound_ZP__TransactionFailedError();
//         }
//         uint256 balanceAfterSupply = vToken.balanceOf(address(this));
//         _supplyTokenInternal(vTokenAddress, balanceAfterSupply, balanceBeforeSupply);
//         emit SuppliedToken(_msgSender(), tokenAddress, amount);
//         return true;
//     }

//     function claimRewardXVS(address vTokenAddress) private returns(uint256) {
//         ICErc20[] memory vTokens = new ICErc20[](1);
//         vTokens[0] = ICErc20(vTokenAddress);
//         uint256 balanceBeforeClaim = _tokenXVS.balanceOf(address(this));
//         _venusComptroller.claimVenus(address(this), vTokens);
//         uint256 balanceAfterClaim = _tokenXVS.balanceOf(address(this));
//         uint256 earnedXVS = balanceAfterClaim - balanceBeforeClaim;
//         return earnedXVS;
//     }

//     function _supplyTokenInternal(
//         address vTokenAddress, 
//         uint256 balanceAfterSupply,
//         uint256 balanceBeforeSupply
//     ) private {
//         uint256 vTokenIssued = (balanceAfterSupply - balanceBeforeSupply);
//         uint256 previousTokenEpoch = previousChildEpoch[vTokenAddress];
//         uint256 userPreviousEpoch = usersInfo[_msgSender()][vTokenAddress].previousChildEpoch;
//         uint256 earnedXVS = claimRewardXVS(vTokenAddress);
//         epochsInfo[vTokenAddress][_childEpoch].vTokenBalance = (
//             epochsInfo[vTokenAddress][previousTokenEpoch].vTokenBalance + vTokenIssued
//         );
//         epochsInfo[vTokenAddress][_childEpoch - 1].rewardDistributionAmount = earnedXVS;
//         userChildEpochBalance[_msgSender()][vTokenAddress][_childEpoch] = (
//             userChildEpochBalance[_msgSender()][vTokenAddress][userPreviousEpoch] + vTokenIssued
//         );
//         previousChildEpoch[vTokenAddress] = _childEpoch;
//     }

//     function withdrawToken(
//         address tokenAddress, 
//         address vTokenAddress, 
//         uint256 amount
//     ) external override nonReentrant returns(bool) {
//         ++_childEpoch;
//         (uint256 userBalance, uint256 userRewardBalance) = calculateUserBalance(vTokenAddress);

//         if(userBalance < amount) {
//             revert Compound_ZP__LowAmountError();
//         }
//         uint256 previousTokenEpoch = previousChildEpoch[vTokenAddress];
//         epochsInfo[vTokenAddress][_childEpoch].vTokenBalance = (
//             epochsInfo[vTokenAddress][previousTokenEpoch].vTokenBalance - amount
//         );

//         uint256 earnedXVS = claimRewardXVS(vTokenAddress);
//         epochsInfo[vTokenAddress][_childEpoch - 1].rewardDistributionAmount = earnedXVS;

//         uint256 userPreviousEpoch = usersInfo[_msgSender()][vTokenAddress].previousChildEpoch;
//         userChildEpochBalance[_msgSender()][vTokenAddress][_childEpoch] = (
//             userChildEpochBalance[_msgSender()][vTokenAddress][userPreviousEpoch] - amount
//         );
//         if (amount == userBalance) {
//             usersInfo[_msgSender()][vTokenAddress].isActiveInvested = false;
//         }

//         usersInfo[_msgSender()][vTokenAddress].rewardWithdrawn += userRewardBalance;
//         _withdrawInternal(tokenAddress, vTokenAddress, amount);
//         _tokenXVS.safeTransfer(_msgSender(), userRewardBalance);
//         return true;
//     }

//     function _withdrawInternal(
//         address tokenAddress,
//         address vTokenAddress,
//         uint256 amount
//     ) private {
//         IERC20Upgradeable token = IERC20Upgradeable(tokenAddress);
//         ICErc20 vToken = ICErc20(vTokenAddress);      
//         uint256 balanceBeforeRedeem = token.balanceOf(address(this));
//         uint256 redeemResult = vToken.redeem(amount);
//         if (redeemResult != 0){
//             revert Compound_ZP__TransactionFailedError();
//         }
//         uint256 balanceAfterRedeem = token.balanceOf(address(this));
//         uint256 amountToBePaid = (balanceAfterRedeem - balanceBeforeRedeem);
//         previousChildEpoch[vTokenAddress] = _childEpoch;
//         token.safeTransfer(_msgSender(), amountToBePaid);  
//     }

//     function calculateUserBalance(
//         address rewardTokenAddress
//     ) public view override returns(uint256, uint256) {
//         uint256 userBalance = 0;
//         uint256 userRewardBalance = 0;
//         uint256 userStartVersion = usersInfo[_msgSender()][rewardTokenAddress].startChildEpoch;
//         uint256 currVersion = _childEpoch;
//         uint256 riskPoolCategory = 0;
//         uint256 parentVersion = 0;
//         for(uint i = userStartVersion; i < currVersion;) {
//             userBalance = (
//                 userChildEpochBalance[_msgSender()][rewardTokenAddress][i] > 0 ? 
//                 userChildEpochBalance[_msgSender()][rewardTokenAddress][i] : userBalance
//             );
//             uint256 rewardEarned = (
//                 (userBalance * epochsInfo[rewardTokenAddress][i].rewardDistributionAmount) / 
//                 epochsInfo[rewardTokenAddress][i].vTokenBalance
//             );
//             userRewardBalance += rewardEarned;
//             uint256 _parentVersion = parentEpoch[i];
//             /// this check ensures that if liquidation has happened on a particular parent version,
//             /// then user needs to liquidated once, not again and again for each child version loop call.
//             if(parentVersion != _parentVersion) {
//                 parentVersion = _parentVersion;
//                 if (_zpController.ifProtocolUpdated(_protocolID, parentVersion)) {
//                     riskPoolCategory = _zpController.getProtocolRiskCategory(_protocolID, parentVersion);
//                 }
//                 if (_zpController.isRiskPoolLiquidated(parentVersion, riskPoolCategory)) {
//                     userBalance = ((userBalance * _zpController.getLiquidationFactor(parentVersion)) / 100);
//                 }
//             }
//             ++i; 
//         }
//         userRewardBalance -= usersInfo[_msgSender()][rewardTokenAddress].rewardWithdrawn;
//         return (userBalance, userRewardBalance);
//     }
// }