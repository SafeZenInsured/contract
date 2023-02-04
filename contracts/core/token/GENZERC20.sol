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

    /*

    100M fixed supply GENZ tokens will be minted to the Buy Contract. 

    */
    uint256 private _initVersion;
    
    function initialize() external initializer {
        __ERC20_init("GenZ Labs", "GENZ");
        __ERC20Permit_init("GENZ");
        __BaseUpgradeablePausable_init(_msgSender());
    }

    error GENZ__ImmutableChangesError();
    function init(address buyContract) external onlyAdmin {
         if (_initVersion > 0) {
            revert GENZ__ImmutableChangesError();
        }
        ++_initVersion;
        _mint(buyContract, 1e25);
    }

    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }
}