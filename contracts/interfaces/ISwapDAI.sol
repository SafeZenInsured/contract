// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

interface ISwapDAI {

    function swapDAI(
        uint256 _amount,
        uint deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external returns(bool);

    function swapsztDAI(
        uint256 _amount,
        uint deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external returns(bool);
}