// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

interface ISwapManager {

    error SwapManager__ZeroAddressInputError();

    error SwapStablecoin__ZeroAddressInputError();

    /// @notice emits when the new token is added for StableSZT ERC20 token purchase
    event NewTokenAdded(uint256 indexed tokenID, address indexed tokenAddress);

    function swapStablecoin(
        uint256 tokenID,
        uint256 amount,
        uint256 deadline, 
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS
    ) external returns(bool);

    function swapStablecoinSZT(
        uint256 tokenID,
        uint256 amount,
        uint256 deadline, 
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS
    ) external returns(bool);
}