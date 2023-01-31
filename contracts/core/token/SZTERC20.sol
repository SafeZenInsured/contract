// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

/// @title SZT ERC20 Token Contract
/// @author Anshik Bansal <anshik@safezen.finance>

/// Importing required contracts
import "./../../BaseUpgradeablePausable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";

/// Report any bug or issues at:
/// @custom:security-contact anshik@safezen.finance
contract SZT is ERC20Upgradeable, ERC20PermitUpgradeable, BaseUpgradeablePausable {

    function initialize(address buySellContractAddress) external initializer {
        __ERC20_init("SafeZen Token", "SZT");
        __ERC20Permit_init("SZT");
        __BaseUpgradeablePausable_init(_msgSender());
        _mint(buySellContractAddress, 21e27);
    }

    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }
}