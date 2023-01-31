// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./interfaces/IGlobalPauseOperation.sol";
import "./BaseUpgradeablePausable.sol";

contract GlobalPauseOperation is BaseUpgradeablePausable, IGlobalPauseOperation {
    bool private _globalPaused;
    uint256 private _initVersion;
    address private _claimGovernanceContract;

    modifier onlyPermittedAddress() {
        require(
            (isAdmin() == true) || 
            (_msgSender() == _claimGovernanceContract)
        );
        _;
    }

    function initialize() external initializer {
        _globalPaused = false;
        __BaseUpgradeablePausable_init(_msgSender());
    }

    function init(address claimGovernance) external onlyAdmin {
        if (_initVersion > 0) {
            revert GlobalPauseOperation__ImmutableChangesError();
        }
        if (claimGovernance == address(0)) {
            revert GlobalPauseOps__ZeroAddressInputError();
        }
        _claimGovernanceContract = claimGovernance;
        ++_initVersion;
    }

    function pauseOperation() external onlyPermittedAddress returns(bool) {
        _globalPaused = true;
        emit PausedOperation(_msgSender());
        return _globalPaused;
    }

    function unpauseOperation() external onlyPermittedAddress returns(bool) {
        _globalPaused = false;
        emit UnpausedOperation(_msgSender());
        return _globalPaused;
    }

    function isPaused() external view override returns(bool) {
        return _globalPaused;
    }
}