// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/// @title Compound Zero Premium Insurance Contract
/// @author Anshik Bansal <anshik@safezen.finance>

/// Importing required interfaces
import "./../../../../interfaces/Compound/ICErc20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./../../../../interfaces/ISmartContractZPController.sol";
import "./../../../../interfaces/Compound/ICompoundImplementation.sol";

/// Importing required contracts
import "./../../../../BaseUpgradeablePausable.sol";

/// Report any bug or issues at:
/// @custom:security-contact anshik@safezen.finance
contract CompoundPool is ICompoundImplementation, BaseUpgradeablePausable {
    uint256 private _protocolID;
    ISmartContractZPController private _zpController;
    
    struct UserInfo {
        bool isActiveInvested;
        uint256 startVersionBlock;
        uint256 withdrawnBalance;
    }

    mapping(address => mapping(address => UserInfo)) private usersInfo;
    /// User Address => Reward Token Address => Version => UserTransactionInfo
    mapping(address => mapping(address => mapping(uint256 => uint256))) private userTokenBalance;

    constructor(address _controllerAddress) {
        _zpController = ISmartContractZPController(_controllerAddress);
    }

    function initialize(
        string memory protocolName,
        address deployedAddress,
        uint256 protocolID
    ) external initializer {
        (string memory _protocolName, address _protocolAddress) = _zpController.getProtocolInfo(protocolID);
        if (_protocolAddress != deployedAddress) {
            revert Compound_ZP__WrongInfoEnteredError();
        }
        if(keccak256(abi.encodePacked(_protocolName)) != keccak256(abi.encodePacked(protocolName))) {
            revert Compound_ZP__WrongInfoEnteredError();
        }
        _protocolID = protocolID;
    }

    function supplyToken(
        address _tokenAddress, 
        address _rewardTokenAddress, 
        uint256 _amount
    ) external override nonReentrant returns(uint256) {
        if (_amount < 1e10) {
            revert Compound_ZP__LowSupplyAmountError();
        }
        uint256 currVersion =  _zpController.latestVersion() + 1;
        if (!usersInfo[_msgSender()][_rewardTokenAddress].isActiveInvested) {
            usersInfo[_msgSender()][_rewardTokenAddress].startVersionBlock = currVersion;
            usersInfo[_msgSender()][_rewardTokenAddress].isActiveInvested = true;
        }
        uint256 balanceBeforeSupply = ICErc20(_rewardTokenAddress).balanceOf(address(this));
        bool transferSuccess = IERC20(_tokenAddress).transferFrom(_msgSender(), address(this), _amount);
        if (!transferSuccess) {
            revert Compound_ZP__TransactionFailedError();
        }
        bool approvalSuccess = IERC20(_tokenAddress).approve(_rewardTokenAddress, _amount);
        if (!approvalSuccess) {
            revert Compound_ZP__TransactionFailedError();
        }
        uint mintResult = ICErc20(_rewardTokenAddress).mint(_amount);
        uint256 balanceAfterSupply = ICErc20(_rewardTokenAddress).balanceOf(address(this));
        userTokenBalance[_msgSender()][_rewardTokenAddress][currVersion] += (balanceAfterSupply - balanceBeforeSupply);
        return mintResult;
    }

    function withdrawToken(
        address _tokenAddress, 
        address _rewardTokenAddress, 
        uint256 _amount
    ) external override nonReentrant returns(uint256) {
        uint256 userBalance = calculateUserBalance(_rewardTokenAddress);
        if (userBalance >= _amount) {
            usersInfo[_msgSender()][_rewardTokenAddress].withdrawnBalance += _amount;
            if (_amount == userBalance) {
                usersInfo[_msgSender()][_rewardTokenAddress].isActiveInvested = false;
            }
            uint256 balanceBeforeRedeem = IERC20(_tokenAddress).balanceOf(address(this));
            uint256 redeemResult = ICErc20(_rewardTokenAddress).redeemUnderlying(_amount);
            if (redeemResult != 0) {
                revert Compound_ZP__TransactionFailedError();
            }
            uint256 balanceAfterRedeem = IERC20(_tokenAddress).balanceOf(address(this));
            uint256 amountToBePaid = (balanceAfterRedeem - balanceBeforeRedeem);
            bool transferSuccess = IERC20(_tokenAddress).transferFrom(address(this), _msgSender(), amountToBePaid);
            if (!transferSuccess) {
                revert Compound_ZP__TransactionFailedError();
            }
            return redeemResult;
        }
        return 404;
    }

    function calculateUserBalance(address _rewardTokenAddress) public view override returns(uint256) {
        uint256 userBalance = 0;
        uint256 userStartVersion = usersInfo[_msgSender()][_rewardTokenAddress].startVersionBlock;
        uint256 currVersion =  _zpController.latestVersion();
        uint256 riskPoolCategory = 0;
        for(uint i = userStartVersion; i <= currVersion;) {
            uint256 userVersionBalance = userTokenBalance[_msgSender()][_rewardTokenAddress][i];
            if (_zpController.ifProtocolUpdated(_protocolID, i)) {
                riskPoolCategory = _zpController.getProtocolRiskCategory(_protocolID, i);
            }
            if (userVersionBalance > 0) {
                userBalance += userVersionBalance;
            } 
            if (_zpController.isRiskPoolLiquidated(i, riskPoolCategory)) {
                userBalance = ((userBalance * _zpController.getLiquidationFactor(i)) / 100);
            } 
            ++i;  
        }
        userBalance -= usersInfo[_msgSender()][_rewardTokenAddress].withdrawnBalance;
        return userBalance;
    }
}