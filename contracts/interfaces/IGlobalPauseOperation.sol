// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IGlobalPauseOperation {

    /// @notice reverts when the function access is restricted to only certain wallet or contract addresses.
    error GlobalPauseOps__AccessRestricted();

    /// @notice reverts when user input wrong token ID which leads to zero address
    error GlobalPauseOps__ZeroAddressInputError();

    /// @notice reverts when init function has already been initialized
    error GlobalPauseOps__InitializedEarlierError();

    event PausedOperation(address account);

    event UnpausedOperation(address account);

    function pauseOperation() external returns(bool);

    function unpauseOperation() external returns(bool);
    
    function isPaused() external view returns(bool);
}