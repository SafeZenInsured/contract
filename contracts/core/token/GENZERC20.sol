// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

/// @title GENZ ERC20 Token Contract
/// @author Anshik Bansal <anshik@safezen.finance>

/// Importing required contracts
import "./../../BaseUpgradeablePausable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";

/// Report any bug or issues at:
/// @custom:security-contact anshik@safezen.finance
contract GENZ is ERC20Upgradeable, ERC20PermitUpgradeable, BaseUpgradeablePausable {

    uint256 private initVersion;
    
    function initialize() external initializer {
        __ERC20_init("GenZ Labs", "GENZ");
        __ERC20Permit_init("GENZ");
        __BaseUpgradeablePausable_init(_msgSender());
    }

    error GENZ__ImmutableChangesError();
    function init(address buyContract) external onlyAdmin {
         if (initVersion > 0) {
            revert GENZ__ImmutableChangesError();
        }
        ++initVersion;
        _mint(buyContract, 1e26);
    }

    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }
}