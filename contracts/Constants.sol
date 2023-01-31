// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

library Constants {

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    function getAdminRole() internal pure returns (bytes32) {
        return ADMIN_ROLE;
    }

    function getPauserRole() internal pure returns (bytes32) {
        return PAUSER_ROLE;
    }
}