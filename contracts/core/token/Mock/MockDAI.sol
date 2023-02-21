// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

/// Importing required interfaces
import "./../../../interfaces/IERC20Extended.sol";

/// Importing required contracts
import "./../../../BaseUpgradeablePausable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";

/// @title Mock ERC20 Token Contract
/// @author Anshik Bansal <anshik@safezen.finance>

/// Report any bug or issues at:
/// @custom:security-contact anshik@safezen.finance
contract MockDAI is ERC20Upgradeable, IERC20Extended, ERC20PermitUpgradeable, BaseUpgradeablePausable {
    
    function initialize(string memory name_, string memory symbol_) external initializer {
        __ERC20_init(name_, symbol_);
        __ERC20Permit_init(symbol_);
        __BaseUpgradeablePausable_init(_msgSender());
        _mint(_msgSender(), 1e26);
    }

    function mint(address to, uint256 amount) external override returns(bool) {
        _mint(to, amount);
        return true;
    }

    function burnFrom(address account, uint256 amount) external override returns(bool) {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
        return true;
    }
}