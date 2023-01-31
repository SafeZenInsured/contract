// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/// @title USDC Zero Premium Insurance Contract
/// @author Anshik Bansal <anshik@safezen.finance>

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./../../../interfaces/IStablecoinZPController.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

error USDC_ZP__LowSupplyAmountError();
error USDC_ZP__WrongInfoEnteredError();
error USDC_ZP__TransactionFailedError();

/// Report any bug or issues at:
/// @custom:security-contact anshik@safezen.finance

// TODO: ADDING EVENTS
contract USDC is Ownable, ReentrancyGuard {
    uint256 private _stablecoinID;  // Unique stablecoin ID
    uint256 private _initVersion = 0;
    IStablecoinZPController private _zpController;  // Zero Premium Controller Interface
    

    /// @dev: Struct storing the user info
    /// @param isActiveInvested: checks if the user has already deposited funds in AAVE via us
    /// @param startVersionBlock: keeps a record with which version user started using our stablecoin
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

    /// @dev initializing contract
    /// @param _controllerAddress: Zero Premium Controller address
    constructor( 
        address _controllerAddress
    ) {
        _zpController = IStablecoinZPController(_controllerAddress);
    }

    // / @dev Initialize this function first before running any other function
    // / @dev Registers the AAVE stablecoin in the Zero Premium Controller stablecoin list
    // / @param stablecoinName: name of the stablecoin: AAVE
    // / @param deployedAddress: address of the AAVE lending pool
    // / @param isCommunityGoverned: checks if the stablecoin is community governed or not
    // / @param riskFactor: registers the risk score of AAVE; 0 being lowest, and 100 being highest
    // / @param riskPoolCategory: registers the risk pool category; 1 - low, 2-medium, and 3- high risk
    function init(
        string memory stablecoinName,
        address deployedAddress,
        uint256 stablecoinID
    ) external onlyOwner {
        if (_initVersion > 0) {
            revert USDC_ZP__TransactionFailedError();
        }
        (string memory _stablecoinName, address _stablecoinAddress) = _zpController.getStablecoinInfo(stablecoinID);
        if (_stablecoinAddress != deployedAddress) {
            revert USDC_ZP__WrongInfoEnteredError();
        }
        if(keccak256(abi.encodePacked(_stablecoinName)) != keccak256(abi.encodePacked(stablecoinName))) {
            revert USDC_ZP__WrongInfoEnteredError();
        }
        _stablecoinID = stablecoinID;
        ++_initVersion;
    }

    /// @dev supply function
    /// @param tokenAddress: token address of the supplied token, e.g. DAI
    /// @param rewardTokenAddress: token address of the received token, e.g. aDAI
    /// @param amount: amount of the tokens supplied
    function supplyToken(
        address tokenAddress, 
        address rewardTokenAddress, 
        uint256 amount
    ) external nonReentrant returns (bool) {
        if (amount < 1e10) {
            revert USDC_ZP__LowSupplyAmountError();
        }
        uint256 currVersion =  _zpController.latestVersion() + 1;
        if (!usersInfo[_msgSender()][rewardTokenAddress].isActiveInvested) {
            usersInfo[_msgSender()][rewardTokenAddress].startVersionBlock = currVersion;
            usersInfo[_msgSender()][rewardTokenAddress].isActiveInvested = true;
        }
        userTransactionInfo[_msgSender()][rewardTokenAddress][currVersion] += amount;
        bool transferSuccess = IERC20(tokenAddress).transferFrom(_msgSender(), address(this), amount);
        if (!transferSuccess) {
            revert USDC_ZP__TransactionFailedError();
        }
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
    ) external nonReentrant returns(bool) {
        uint256 userBalance = calculateUserBalance(rewardTokenAddress);
        if (userBalance < amount) {
            revert USDC_ZP__TransactionFailedError();
        }
        usersInfo[_msgSender()][rewardTokenAddress].withdrawnBalance += amount;
        if (amount == userBalance) {
            usersInfo[_msgSender()][rewardTokenAddress].isActiveInvested = false;
        }
        bool success = IERC20(tokenAddress).transfer(_msgSender(), amount);
        if (!success) {
            revert USDC_ZP__TransactionFailedError();
        }
        return true;
    }
    
    /// @dev calculates the user balance
    /// @param rewardTokenAddress: token address of the token received, e.g. aDAI
    function calculateUserBalance(
        address rewardTokenAddress
    ) public view returns(uint256) {
        uint256 userBalance = 0;
        uint256 userStartVersion = usersInfo[_msgSender()][rewardTokenAddress].startVersionBlock;
        uint256 currVersion =  _zpController.latestVersion();
        uint256 riskPoolCategory = 0;
        for(uint i = userStartVersion; i <= currVersion;) {
            uint256 userVersionBalance = userTransactionInfo[_msgSender()][rewardTokenAddress][i];
            if (_zpController.ifStablecoinUpdated(_stablecoinID, i)) {
                riskPoolCategory = _zpController.getStablecoinRiskCategory(_stablecoinID, i);
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