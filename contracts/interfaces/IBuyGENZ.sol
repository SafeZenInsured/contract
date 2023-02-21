// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

/// @title Buy GENZ Contract
/// @author Anshik Bansal <anshik@safezen.finance>

interface IBuyGENZ {
    
    // ::::::::::::::::::::::: CUSTOM ERROR CODE :::::::::::::::::::::::: //

    /// @notice reverts when the certain operation & functions has been paused.
    error BuyGENZ__OperationPaused();

    /// @notice reverts when user input wrong token ID which leads to zero address
    error BuyGENZ__ZeroAddressInputError();

    /// @notice reverts when user tries to withdraw token without purchasing GENZ token
    error BuyGENZ__ZeroTokensPurchasedError();

    /// @notice reverts when user input amount less than the minimum acceptable amount
    error BuyGENZ__LessThanMinimumAmountError();

    error BuyGENZ__GENZBuyOperationFailedError();

    /// @notice reverts when user is not having sufficient DAI ERC20 token to purchase GENZ token
    error BuySellGENZ__InsufficientBalanceError();

    /// @notice reverts when user tries to withdraw GENZ token before the minimum withdrawal time
    error BuyGENZ__EarlyWithdrawalRequestedError();    

    error BuyGENZ__GENZWithdrawOperationFailedError();
    
    // :::::::::::::::::::::::: CUSTOM EVENTS ::::::::::::::::::::::::::: //

    /// @notice emits after the funds have been withdrawn
    /// @param to: to address
    /// @param amount: amount of tokens transferred
    event FundsTransferred(
        address indexed to,
        uint256 indexed amount
    );

    /// @notice emits after the contract has been initialized
    event InitializedContractBuyGENZ(address indexed adminAddress);

    /// @notice emits after the GENZ base sale price gets updated 
    event UpdatedBaseSalePrice(uint256 indexed updatedTokenPrice);

    /// @notice emits when the minimum withdrawal period time limit gets updated
    event UpdatedMinimumWithdrawalPeriod(uint256 indexed timeInDays);

    /// @notice emits when the sale cap gets updated
    event UpdatedSaleCap(uint256 indexed updatedSaleCap);

    /// @notice emits when the new token is added for GENZ ERC20 token purchase
    event NewTokenAdded(uint256 indexed tokenID, address indexed tokenAddress);

    /// @notice emits when the bonus token period gets updated
    event UpdatedBonusTokenPeriod(uint256 indexed timeInHours);

    /// @notice emits when the bonus token percent gets updated
    event UpdatedBonusTokenPercent(uint256 indexed updatedPercent);

    /// @notice emits after the GENZ token has been bought
    /// @param addressUser: user wallet address
    /// @param amountInGENZ: amount of GENZ tokens user has purchased
    event BoughtGENZ(
        address indexed addressUser,
        uint256 indexed amountInGENZ
    );

    /// @notice emits after the GENZ token has been transferred to user
    /// @param addressUser: user wallet address
    /// @param amountInGENZ: amount of GENZ tokens user has withdrawn
    event WithdrawnGENZ(
        address indexed addressUser,
        uint256 indexed amountInGENZ
    );


    // :::::::::::::::::::::::::: FUNCTIONS ::::::::::::::::::::::::::::: //

    /// @dev this function faciliate users' to buy GENZ ERC20 token
    /// @param value: amount of GENZ ERC20 tokens user wishes to purchase
    /// @param deadline: DAI ERC20 token permit deadline
    /// @param permitV: DAI ERC20 token permit signature (value v)
    /// @param permitR: DAI ERC20 token permit signature (value r)
    /// @param permitS: DAI ERC20 token permit signature (value s)
    function buyTokenGENZ(
        uint256 tokenID,
        uint256 value,
        uint deadline, 
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS
    ) external;

    /// @dev this function aims to faciliate users' GENZ token withdrawal to their respcective wallets
    function withdrawTokens() external;


    // :::::::::::::::::::::::: END OF INTERFACE :::::::::::::::::::::::: //

}