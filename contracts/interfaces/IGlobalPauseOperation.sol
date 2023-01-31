// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IGlobalPauseOperation {

    error GlobalPauseOps__ZeroAddressInputError();

    error GlobalPauseOperation__ImmutableChangesError();

    event PausedOperation(address account);

    event UnpausedOperation(address account);

    function pauseOperation() external returns(bool);

    function unpauseOperation() external returns(bool);
    
    function isPaused() external view returns(bool);
}