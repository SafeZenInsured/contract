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

    /// _tokenSZTDAI: SZTDAI ERC20 token interface
    /// _tokenDAI: DAI ERC20 token interface
    /// _tokenPermitDAI: DAI ERC20 token interface with permit
    /// _tokenPermitSZTDAI: SZTDAI ERC20 token interface with permit
    IERC20Extended private immutable _tokenSZTDAI;
    IERC20Upgradeable private immutable _tokenDAI;
    IERC20PermitUpgradeable private immutable _tokenPermitDAI;
    IERC20PermitUpgradeable private immutable _tokenPermitSZTDAI;

    /// @custom:oz-upgrades-unsafe-allow-constructor
    /// addressDAI: address of the DAI ERC20 token
    /// addressSZTDAI: address of the SZTDAI ERC20 token
    constructor(address addressDAI, address addressSZTDAI) {
        _tokenSZTDAI = IERC20Extended(addressSZTDAI);
        _tokenDAI = IERC20Upgradeable(addressDAI);
        _tokenPermitDAI = IERC20PermitUpgradeable(addressDAI);
        _tokenPermitSZTDAI = IERC20PermitUpgradeable(addressSZTDAI);
    }

    /// @dev this function aims to pause the contracts' certain functions temporarily
    function pause() external onlyAdmin {
        _pause();
    }

    /// @dev this function aims to resume the complete contract functionality
    function unpause() external onlyAdmin {
        _unpause();
    }

    /// @notice this function aims to swap DAI to SZT DAI
    /// @param amount: amount of DAI ERC20 token user wishes to swap
    /// @param deadline: DAI ERC20 token permit deadline
    /// @param permitV: DAI ERC20 token permit signature (value v)
    /// @param permitR: DAI ERC20 token permit signature (value r)
    /// @param permitS: DAI ERC20 token permit signature (value s)
    function swapDAI(
        uint256 amount,
        uint256 deadline, 
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS
    ) external override returns(bool) {
        _tokenPermitDAI.safePermit(_msgSender(), address(this), amount, deadline, permitV, permitR, permitS);
        _tokenDAI.safeTransferFrom(_msgSender(), address(this), amount);
        bool mintSuccess = _tokenSZTDAI.mint(_msgSender(), amount);
        if (!mintSuccess) {
            revert SwapDAI__TransactionFailedError();
        }
        return true;
    }

    /// @notice this function aims to swap DAI to SZT DAI
    /// @param amount: amount of _tokenSZTDAI ERC20 token user wishes to swap
    /// @param deadline: _tokenSZTDAI ERC20 token permit deadline
    /// @param permitV: _tokenSZTDAI ERC20 token permit signature (value v)
    /// @param permitR: _tokenSZTDAI ERC20 token permit signature (value r)
    /// @param permitS: _tokenSZTDAI ERC20 token permit signature (value s)
    function swapSZTDAI(
        uint256 amount,
        uint256 deadline, 
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS
    ) external override returns(bool) {
        _tokenPermitSZTDAI.safePermit(_msgSender(), address(this), amount, deadline, permitV, permitR, permitS);
        _tokenSZTDAI.safeTransferFrom(_msgSender(), address(this), amount);
        _tokenDAI.safeTransfer(_msgSender(), amount);
        return true;
    }
}