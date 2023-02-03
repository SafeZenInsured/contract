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
error ERC20__ImmutableChangesError();
error ERC20__SameAdressTransferError();
error ERC20__InsufficientBalanceError();

/// Report any bug or issues at:
/// @custom:security-contact anshik@safezen.finance

contract SZTDAI is ERC20Upgradeable, IERC20Extended, ERC20PermitUpgradeable, BaseUpgradeablePausable {
    uint256 private _initVersion;
    address public swapContractDAI;
    ICFA private _contractFlowAgreement;

    modifier onlyPermissioned() {
        require(
            (_msgSender() == swapContractDAI) || 
            (_msgSender() == address(_contractFlowAgreement))
        );
        _;
    }

    function initialize() external initializer {
        __ERC20_init("SZT DAI Stream Token", "SZTDAI");
        __ERC20Permit_init("SZTDAI");
        __BaseUpgradeablePausable_init(_msgSender());
    }

    function init(
        address _addressSwapDAI,
        address _addressCFA
    ) external onlyAdmin {
        if (_initVersion > 0) {
            revert ERC20__ImmutableChangesError();
        }
        ++_initVersion;
        swapContractDAI = _addressSwapDAI;
        _contractFlowAgreement = ICFA(_addressCFA);
    }

    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }
    
    //// check onlyPermissioned if needed or not
    function mint(address to, uint256 amount) external onlyPermissioned override returns(bool) {
        _mint(to, amount);
        return true;
    }

    function burnFrom(address account, uint256 amount) external override returns(bool) {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
        return true;
    }

    function transfer(
        address to, 
        uint256 amount
    ) public override(ERC20Upgradeable, IERC20Upgradeable) returns(bool) {
        address owner = _msgSender();
        uint256 userCurrentBalance = balanceOf(_msgSender());
        uint256 userPremiumCost = _contractFlowAgreement.getGlobalUserInsurancePremiumCost(_msgSender());
        if ((userCurrentBalance - userPremiumCost) < amount) {
            revert ERC20__InsufficientBalanceError();
        }
        _transfer(owner, to, amount);
        return true;
    }

    function transferFrom(
        address from, 
        address to, 
        uint256 amount
    ) public override(ERC20Upgradeable, IERC20Upgradeable) returns(bool) {
        if (to == from) {
            revert ERC20__SameAdressTransferError();
        }
        uint256 userCurrentBalance = balanceOf(from);
        uint256 userPremiumCost = _contractFlowAgreement.getGlobalUserInsurancePremiumCost(from);
        if ((userCurrentBalance - userPremiumCost) < amount) {
            revert ERC20__InsufficientBalanceError();
        }
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }
}