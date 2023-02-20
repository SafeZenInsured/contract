// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./interfaces/IGlobalPauseOperation.sol";
import "./BaseUpgradeablePausable.sol";

contract GlobalPauseOperation is BaseUpgradeablePausable, IGlobalPauseOperation {
    bool private _globalPaused;
    uint256 public initVersion;
    address public claimGovernance;

    function initialize() external initializer {
        _globalPaused = false;
        __BaseUpgradeablePausable_init(_msgSender());
    }

    function init(address addressClaimGovernance) external onlyAdmin {
        if (initVersion > 0) {
            revert GlobalPauseOps__InitializedEarlierError();
        }
        if (claimGovernance == address(0)) {
            revert GlobalPauseOps__ZeroAddressInputError();
        }
        claimGovernance = addressClaimGovernance;
        ++initVersion;
    }

    function pauseOperation() external returns(bool) {
        _isPermitted();
        _globalPaused = true;
        emit PausedOperation(_msgSender());
        return _globalPaused;
    }

    function unpauseOperation() external returns(bool) {
        _isPermitted();
        _globalPaused = false;
        emit UnpausedOperation(_msgSender());
        return _globalPaused;
    }

    function isPaused() external view override returns(bool) {
        return _globalPaused;
    }

    /// @notice this function restricts function calls accessible to the coverage pool contract address only.
    function _isPermitted() private view {
        if((!isAdmin()) && (_msgSender() != claimGovernance)) {
            revert GlobalPauseOps__AccessRestricted();
        }
    }
}