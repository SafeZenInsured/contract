// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

interface ISwapDAI {

    function swapDAI(
        uint256 _amount,
        uint256 deadline, 
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS
    ) external returns(bool);

    function swapSZTDAI(
        uint256 _amount,
        uint256 deadline, 
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS
    ) external returns(bool);
}