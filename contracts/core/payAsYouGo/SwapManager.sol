// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/// @title Swap DAI Contract
/// @author Anshik Bansal <anshik@safezen.finance>

/// Importing required interfaces
import "./../../interfaces/ISwapManager.sol";
import "./../../interfaces/IERC20Extended.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

/// Importing required contract
import "./../../BaseUpgradeablePausable.sol";

error SwapDAI__TransactionFailedError();

contract SwapManager is ISwapManager, BaseUpgradeablePausable {

    // ::::::::::::::::: STATE VARIABLES AND DECLARATIONS :::::::::::::::: //

    using SafeERC20Upgradeable for IERC20Extended;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeERC20Upgradeable for IERC20PermitUpgradeable;

    /// tokenID: unique token ID for acceptable token addresses
    /// tokenStableSZT: StableSZT ERC20 token interface
    /// tokenPermitStableSZT: SZTDAI ERC20 token interface with permit
    uint256 public tokenID;
    IERC20Extended public immutable tokenStableSZT;
    IERC20PermitUpgradeable public immutable tokenPermitStableSZT;

    /// @notice mapping: uint256 tokenID => address addressToken
    mapping(uint256 => address) public permissionedTokens;

    /// @custom:oz-upgrades-unsafe-allow-constructor
    /// addressDAI: address of the DAI ERC20 token
    /// addressStableSZT: address of the SZTDAI ERC20 token
    constructor(address addressStableSZT) {
        tokenStableSZT = IERC20Extended(addressStableSZT);
        tokenPermitStableSZT = IERC20PermitUpgradeable(addressStableSZT);
    }

    /// @notice this function facilitates adding new supported payment tokens for StableSZT ERC20 token purchase
    /// @param addressToken: ERC20 stablecoin address
    function addTokenAddress(address addressToken) external onlyAdmin {
        if(addressToken == address(0)) {
            revert SwapManager__ZeroAddressInputError();
        }
        ++tokenID;
        permissionedTokens[tokenID] = addressToken;
        emit NewTokenAdded(tokenID, addressToken);
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
    function swapStablecoin(
        uint256 tokenID_,
        uint256 amount,
        uint256 deadline, 
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS
    ) external override returns(bool) {
        address tokenAddress = permissionedTokens[tokenID_];
        if(tokenAddress == address(0)) {
            revert SwapStablecoin__ZeroAddressInputError();
        }
        IERC20Upgradeable token = IERC20Upgradeable(tokenAddress);
        IERC20PermitUpgradeable tokenWithPermit = IERC20PermitUpgradeable(tokenAddress);
        tokenWithPermit.safePermit(_msgSender(), address(this), amount, deadline, permitV, permitR, permitS);
        token.safeTransferFrom(_msgSender(), address(this), amount);
        bool mintSuccess = tokenStableSZT.mint(_msgSender(), amount);
        if (!mintSuccess) {
            revert SwapDAI__TransactionFailedError();
        }
        return true;
    }

    /// @notice this function aims to swap DAI to SZT DAI
    /// @param amount: amount of tokenStableSZT ERC20 token user wishes to swap
    /// @param deadline: tokenStableSZT ERC20 token permit deadline
    /// @param permitV: tokenStableSZT ERC20 token permit signature (value v)
    /// @param permitR: tokenStableSZT ERC20 token permit signature (value r)
    /// @param permitS: tokenStableSZT ERC20 token permit signature (value s)
    function swapStableSZT(
        uint256 tokenID_,
        uint256 amount,
        uint256 deadline, 
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS
    ) external override returns(bool) {
        address tokenAddress = permissionedTokens[tokenID_];
        if(tokenAddress == address(0)) {
            revert SwapStablecoin__ZeroAddressInputError();
        }
        IERC20Upgradeable token = IERC20Upgradeable(tokenAddress);
        tokenPermitStableSZT.safePermit(_msgSender(), address(this), amount, deadline, permitV, permitR, permitS);
        tokenStableSZT.safeTransferFrom(_msgSender(), address(this), amount);
        token.safeTransfer(_msgSender(), amount);
        return true;
    }
}