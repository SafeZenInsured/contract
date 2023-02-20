// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

/// @title: sztDAI ERC20 Token Contract
/// @author: Anshik Bansal <anshik@safezen.finance>

/// Importing required interfaces
import "./../../interfaces/ICFA.sol";
import "./../../interfaces/IERC20Extended.sol";

/// Importing required contracts
import "./../../BaseUpgradeablePausable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";

/// Custom Error Codes

/// @notice reverts when the function access is restricted to only certain wallet or contract addresses.
error ERC20__AccessRestricted();

/// @notice reverts when init function has already been initialized.
error ERC20__InitializedEarlierError();

/// @notice reverts when the sender and recepient addresses are same.
error ERC20__SameAdressTransferError();

/// @notice reverts when user is not having sufficient accepted stablecoin, e.g., DAI ERC20 token to swap token
error ERC20__InsufficientBalanceError();

/// Report any bug or issues at:
/// @custom:security-contact anshik@safezen.finance

contract StableSZT is ERC20Upgradeable, IERC20Extended, ERC20PermitUpgradeable, BaseUpgradeablePausable {

    // ::::::::::::::::: STATE VARIABLES AND DECLARATIONS :::::::::::::::: //

    /// swapManager: Swap Manager contract interface
    /// initCounter: counter to initialize the init one-time function, max value can be 1.
    /// constantFlowAgreement: Constant Flow Agreement contract interface
    address public swapManager;
    uint256 public initCounter;
    ICFA public constantFlowAgreement;

    // :::::::::::::::::::::::: WRITING FUNCTIONS :::::::::::::::::::::::: //

    // ::::::::::::::::::::::::: ADMIN FUNCTIONS ::::::::::::::::::::::::: //

    /// @notice initialize function, called during the contract initialization
    function initialize() external initializer {
        __ERC20_init("StableSZT Stream Token", "StableSZT");
        __ERC20Permit_init("StableSZT");
        __BaseUpgradeablePausable_init(_msgSender());
    }

    /// @notice one time function to initialize the contract
    /// @param addressSwapManager: Swap Manager contract address
    /// @param addressCFA: Constant Flow Agreement contract address
    function init(
        address addressSwapManager,
        address addressCFA
    ) external onlyAdmin {
        if (initCounter > 0) {
            revert ERC20__InitializedEarlierError();
        }
        ++initCounter;
        swapManager = addressSwapManager;
        constantFlowAgreement = ICFA(addressCFA);
    }

    /// @notice to pause the certain functions within the contract
    function pause() external onlyAdmin {
        _pause();
    }

    /// @notice to unpause the certain functions paused earlier within the contract
    function unpause() external onlyAdmin {
        _unpause();
    }

    // :::::::::::::::::::::::: EXTERNAL FUNCTIONS ::::::::::::::::::::::: //

    
    //// @notice this function aims to mint the StableSZT ERC20 tokens to the requested address.
    /// @param to: destination wallet address
    /// @param amount: amount of StableSZT ERC20 token user wishes to purchase 
    function mint(address to, uint256 amount) external override returns(bool) {
        _isPermitted();
        _mint(to, amount);
        return true;
    }

    /// notice this function aims to burn the StableSZT ERC20 tokens
    function burnFrom(address account, uint256 amount) external override returns(bool) {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
        return true;
    }

    /// @notice this function facilitates user to transfer StableSZT to the recepient address.
    /// @param to: recepient wallet address
    /// @param amount: amount of StableSZT ERC20 token to transfer
    function transfer(
        address to, 
        uint256 amount
    ) public override(ERC20Upgradeable, IERC20Upgradeable) returns(bool) {
        address owner = _msgSender();
        uint256 userCurrentBalance = balanceOf(_msgSender());
        uint256 userPremiumCost = constantFlowAgreement.getGlobalUserInsurancePremiumCost(_msgSender());
        if ((userCurrentBalance - userPremiumCost) < amount) {
            revert ERC20__InsufficientBalanceError();
        }
        _transfer(owner, to, amount);
        return true;
    }

    /// @notice this function facilitates users to transfer funds from the sender to the recepient wallet address
    /// @param from: sender wallet address
    /// @param to: recepient wallet address
    /// @param amount: amount of StableSZT ERC20 token to transfer
    function transferFrom(
        address from, 
        address to, 
        uint256 amount
    ) public override(ERC20Upgradeable, IERC20Upgradeable) returns(bool) {
        if (to == from) {
            revert ERC20__SameAdressTransferError();
        }
        uint256 userCurrentBalance = balanceOf(from);
        uint256 userPremiumCost = constantFlowAgreement.getGlobalUserInsurancePremiumCost(from);
        if ((userCurrentBalance - userPremiumCost) < amount) {
            revert ERC20__InsufficientBalanceError();
        }
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }
    
    /// @notice this function restricts function calls accessible to the \
    /// Swap Manager and Constant Flow Agreement contract address only.
    function _isPermitted() private view {
        if(
            (_msgSender() != address(swapManager)) && 
            (_msgSender() != address(constantFlowAgreement))
        ) {
            revert ERC20__AccessRestricted();
        }
    }
}