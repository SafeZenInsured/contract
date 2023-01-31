// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/// @title Swap DAI Contract
/// @author Anshik Bansal <anshik@safezen.finance>

/// Importing required interfaces
import "./../../interfaces/ISwapDAI.sol";
import "./../../interfaces/IERC20Extended.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

/// Importing required contract
import "./../../BaseUpgradeablePausable.sol";

error SwapDAI__TransactionFailedError();

contract SwapDAI is ISwapDAI, BaseUpgradeablePausable {
    using SafeERC20Upgradeable for IERC20Extended;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeERC20Upgradeable for IERC20PermitUpgradeable;

    IERC20Extended private immutable sztDAI;
    IERC20Upgradeable private immutable tokenDAI;
    IERC20PermitUpgradeable private immutable tokenDAIPermit;
    IERC20PermitUpgradeable private immutable sztDAIPermit;

    /// @custom:oz-upgrades-unsafe-allow-constructor
    constructor(address addressDAI, address addressSZTDAI) {
        sztDAI = IERC20Extended(addressSZTDAI);
        tokenDAI = IERC20Upgradeable(addressDAI);
        tokenDAIPermit = IERC20PermitUpgradeable(addressDAI);
        sztDAIPermit = IERC20PermitUpgradeable(addressSZTDAI);
    }

    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }

    function swapDAI(
        uint256 _amount,
        uint deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external override returns(bool) {
        tokenDAIPermit.safePermit(_msgSender(), address(this), _amount, deadline, v, r, s);
        tokenDAI.safeTransferFrom(_msgSender(), address(this), _amount);
        bool mintSuccess = sztDAI.mint(_msgSender(), _amount);
        if (!mintSuccess) {
            revert SwapDAI__TransactionFailedError();
        }
        return true;
    }

    function swapsztDAI(
        uint256 _amount,
        uint deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external override returns(bool) {
        sztDAIPermit.safePermit(_msgSender(), address(this), _amount, deadline, v, r, s);
        sztDAI.safeTransferFrom(_msgSender(), address(this), _amount);
        tokenDAI.safeTransfer(_msgSender(), _amount);
        return true;
    }
}