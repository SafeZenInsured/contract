// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.16;

interface IAAVEImplementation {

    // :::::::::::::::::::::::: CUSTOM ERROR CODE :::::::::::::::::::::::: //

    error AAVE_ZP__OperationPaused();
    
    error AAVE_ZP__TokenSupplyFailed();

    error AAVE_ZP__WrongInfoEnteredError();

    error AAVE_ZP__InitializedEarlierError();

    error AAVE_ZP__LessThanMinimumAmountError();

    error AAVE_ZP__TokenSupplyOperationReverted();

    error AAVE_ZP__RewardClaimOperationReverted();

    error AAVE_ZP__IncorrectAddressesInputError();

    error AAVE_ZP__TokenWithdrawalOperationReverted();

    // :::::::::::::::::::::::::: CUSTOM EVENTS :::::::::::::::::::::::::: //

    event SuppliedToken(
        address indexed userAddress, 
        address indexed tokenAddress,
        uint256 indexed amount
    );

    event WithdrawnToken(
        address indexed userAddress, 
        address indexed tokenAddress,
        uint256 indexed amount
    );

    // :::::::::::::::::::::::: WRITING FUNCTIONS :::::::::::::::::::::::: //
    
    // :::::::::::::::::::::::: EXTERNAL FUNCTIONS ::::::::::::::::::::::: //
    
    function supplyToken(
        address tokenAddress, 
        address rewardTokenAddress, 
        uint256 amount,
        uint256 deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external;

    function withdrawToken(
        address tokenAddress, 
        address rewardTokenAddress, 
        uint256 _amount
    ) external;

}