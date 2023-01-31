// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/// @title AAVE Zero Premium Insurance Contract
/// @author Anshik Bansal <anshik@safezen.finance>

/// Importing required interfaces
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./../../../../interfaces/AAVE/IAAVEV3INTERFACE.sol";
import "./../../../../interfaces/AAVE/IAAVEImplementation.sol"; 
import "./../../../../interfaces/ISmartContractZPController.sol"; 

/// Importing required contracts
import "./../../../../BaseUpgradeablePausable.sol";

error AAVE_ZP__LowSupplyAmountError();
error AAVE_ZP__WrongInfoEnteredError();
error AAVE_ZP__TransactionFailedError();

/// Report any bug or issues at:
/// @custom:security-contact anshik@safezen.finance

// TODO: ADDING EVENTS
contract AAVE is IAAVEImplementation, BaseUpgradeablePausable {
    uint256 private _protocolID;  // Unique Protocol ID
    uint256 private _initVersion;
    IAAVEV3INTERFACE private _interfaceAAVEV3;  // AAVE v3 Supply and Withdraw Interface
    ISmartContractZPController private _zpController;  // Zero Premium Controller Interface
    

    /// @dev: Struct storing the user info
    /// @param isActiveInvested: checks if the user has already deposited funds in AAVE via us
    /// @param startVersionBlock: keeps a record with which version user started using our protocol
    /// @param withdrawnBalance: keeps a record of the amount the user has withdrawn
    struct UserInfo {
        bool isActiveInvested;
        uint256 startVersionBlock;
        uint256 withdrawnBalance;
    }

    /// Maps --> User Address => Reward Token Address => UserInfo struct
    mapping(address => mapping(address => UserInfo)) private usersInfo;
    /// Maps --> User Address => Reward Token Address => Version => UserTransactionInfo
    mapping(address => mapping(address => mapping(uint256 => uint256))) private userTransactionInfo;

    /// Maps reward address => version => reward balance
    mapping(address => mapping(uint256 => uint256)) private rewardInfo;

    /// @dev Initialize this function first before running any other function
    /// @dev Registers the AAVE protocol in the Zero Premium Controller protocol list
    /// @param protocolName: name of the protocol: AAVE
    /// @param deployedAddress: address of the AAVE lending pool
    /// @dev initializing contract with AAVE v3 lending pool address and Zero Premium controller address
    /// @param _lendingAddress: AAVE v3 lending address
    /// @param _controllerAddress: Zero Premium Controller address
    function initialize(
        address _lendingAddress, 
        address _controllerAddress,
        string memory protocolName,
        address deployedAddress,
        uint256 protocolID
    ) external initializer {
        _interfaceAAVEV3 = IAAVEV3INTERFACE(_lendingAddress);
        _zpController = ISmartContractZPController(_controllerAddress);
        (string memory _protocolName, address _protocolAddress) = _zpController.getProtocolInfo(protocolID);
        if (_protocolAddress != deployedAddress) {
            revert AAVE_ZP__WrongInfoEnteredError();
        }
        if(keccak256(abi.encodePacked(_protocolName)) != keccak256(abi.encodePacked(protocolName))) {
            revert AAVE_ZP__WrongInfoEnteredError();
        }
        _protocolID = protocolID;
    }


    // function mintERC20Tokens(address tokenAddress, uint256 amount) public override {
    //     IAAVEERC20(tokenAddress).mint(msg.sender, amount);
    // }


    /// @dev supply function to supply token to the AAVE v3 Pool
    /// @param tokenAddress: token address of the supplied token, e.g. DAI
    /// @param rewardTokenAddress: token address of the received token, e.g. aDAI
    /// @param amount: amount of the tokens supplied
    function supplyToken(
        address tokenAddress, 
        address rewardTokenAddress, 
        uint256 amount
    ) external override nonReentrant returns (bool) {
        if (amount < 1e10) {
            revert AAVE_ZP__LowSupplyAmountError();
        }
        /// TODO: updating the latest version in Zero Premium Controller.
        uint256 currVersion =  _zpController.latestVersion() + 1;
        if (!usersInfo[_msgSender()][rewardTokenAddress].isActiveInvested) {
            usersInfo[_msgSender()][rewardTokenAddress].startVersionBlock = currVersion;
            usersInfo[_msgSender()][rewardTokenAddress].isActiveInvested = true;
        }
        uint256 balanceBeforeSupply = IERC20(rewardTokenAddress).balanceOf(address(this));
        bool transferSuccess = IERC20(tokenAddress).transferFrom(_msgSender(), address(this), amount);
        if (!transferSuccess) {
            revert AAVE_ZP__TransactionFailedError();
        }
        bool approvalSuccess = IERC20(tokenAddress).approve(address(_interfaceAAVEV3), amount);
        if (!approvalSuccess) {
            revert AAVE_ZP__TransactionFailedError();
        }
        _interfaceAAVEV3.supply(tokenAddress, amount, address(this), 0);
        uint256 balanceAfterSupply = IERC20(rewardTokenAddress).balanceOf(address(this));
        userTransactionInfo[_msgSender()][rewardTokenAddress][currVersion] += (balanceAfterSupply - balanceBeforeSupply);
        return true;
    }

    /// @dev to withdraw the tokens from the AAVE v3 lending pool
    /// @param tokenAddress: token address of the supplied token, e.g. DAI
    /// @param rewardTokenAddress: token address of the received token, e.g. aDAI
    /// @param amount: amount of the tokens to be withdrawn
    function withdrawToken(
        address tokenAddress, 
        address rewardTokenAddress, 
        uint256 amount
    ) external nonReentrant override returns(bool) {
        uint256 userBalance = calculateUserBalance(rewardTokenAddress);
        if (userBalance >= amount) {
            usersInfo[_msgSender()][rewardTokenAddress].withdrawnBalance += amount;
            if (amount == userBalance) {
                usersInfo[_msgSender()][rewardTokenAddress].isActiveInvested = false;
            }
            bool approvalSuccess = IERC20(rewardTokenAddress).approve(address(_interfaceAAVEV3), amount);
            if (!approvalSuccess) {
                revert AAVE_ZP__TransactionFailedError();
            }
            _interfaceAAVEV3.withdraw(tokenAddress, amount, address(this));
            bool success = IERC20(tokenAddress).transfer(_msgSender(), amount);
            if (!success) {
                revert AAVE_ZP__TransactionFailedError();
            }
            return true;
        }     
        return false;   
    }
    
    /// @dev calculates the user balance
    /// @param rewardTokenAddress: token address of the token received, e.g. aDAI
    function calculateUserBalance(
        address rewardTokenAddress
    ) public view override returns(uint256) {
        uint256 userBalance = 0;
        uint256 userStartVersion = usersInfo[_msgSender()][rewardTokenAddress].startVersionBlock;
        uint256 currVersion =  _zpController.latestVersion();
        uint256 riskPoolCategory = 0;
        for(uint i = userStartVersion; i <= currVersion;) {
            uint256 userVersionBalance = userTransactionInfo[_msgSender()][rewardTokenAddress][i];
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
        userBalance -= usersInfo[_msgSender()][rewardTokenAddress].withdrawnBalance;
        return userBalance;
    }
}