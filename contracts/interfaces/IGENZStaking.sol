// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

interface IGENZStaking {

    event UpdatedWithdrawTimer(uint256 indexed timeInMinutes);

    event UpdatedMinStakingAmount(uint256 indexed value);

    event StakedGENZ(address indexed userAddress, uint256 value);

    event UnstakedGENZ(address indexed userAddress, uint256 value);

    function stakeGENZ(uint256 _value) external returns(bool);

    function activateWithdrawalTimer(uint256 _value) external returns(bool);

    function withdrawGENZ(uint256 _value) external returns(bool);

}