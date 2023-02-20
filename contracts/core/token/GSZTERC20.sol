// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

/// @title GSZT ERC20 Token Contract
/// @author Anshik Bansal <anshik@safezen.finance>

/// Importing required interfaces
import "./../../interfaces/IERC20Extended.sol";

/// Importing required contracts
import "./../../BaseUpgradeablePausable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";

error ERC20__ZeroAddressError();
error ERC20__TransactionFailedError();
error ERC20__SameAdressTransferError();

/// Report any bug or issues at:
/// @custom:security-contact anshik@safezen.finance
contract GSZT is ERC20Upgradeable, IERC20Extended, ERC20PermitUpgradeable, BaseUpgradeablePausable {
    address public buySZTCA;

    modifier onlyPermissioned() {
        require(_msgSender() == buySZTCA);
        _;
    }

    function initialize(
        address addressBuySellSZT
    ) external initializer {
        __ERC20_init("SafeZen Governance Token", "GSZT");
        __ERC20Permit_init("GSZT");
        __BaseUpgradeablePausable_init(_msgSender());
        buySZTCA = addressBuySellSZT;
    }
    
    function mint(address to, uint256 amount) external override onlyPermissioned returns(bool) {
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
    ) public override(ERC20Upgradeable, IERC20Upgradeable) returns (bool) {
        if (to != buySZTCA) {
            revert ERC20__TransactionFailedError();
        }
        address owner = _msgSender();
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
        if (to != buySZTCA) {
            revert ERC20__TransactionFailedError();
        }
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }

}