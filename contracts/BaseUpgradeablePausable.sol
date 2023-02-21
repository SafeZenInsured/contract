// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "./Constants.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

error BaseUpgradeablePausable__ZeroAddressError();

contract BaseUpgradeablePausable is 
    Initializable, 
    PausableUpgradeable, 
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable 
{

    modifier onlyAdmin() {
        require(isAdmin(), "Must have admin role to perform this action.");
        _;
    }

    function __BaseUpgradeablePausable_init(address owner) public onlyInitializing() {
        if(owner == address(0)) {
            revert BaseUpgradeablePausable__ZeroAddressError();
        }
        __Pausable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();

        _grantRole(Constants.getAdminRole(), owner);
        _grantRole(Constants.getPauserRole(), owner);

        _setRoleAdmin(Constants.getPauserRole(), Constants.getAdminRole());
        _setRoleAdmin(Constants.getAdminRole(), Constants.getAdminRole());
    }

    function isAdmin() public view returns (bool) {
        return hasRole(Constants.getAdminRole(), _msgSender());
    }

    function isModerator() public view returns (bool) {
        return hasRole(Constants.getPauserRole(), _msgSender());
    }

}