// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

/// @title Buy GENZ Contract
/// @author Anshik Bansal <anshik@safezen.finance>

interface IBuyGENZ {
    
    // ::::::::::::::::::::::: CUSTOM ERROR CODE :::::::::::::::::::::::: //

    /// @notice reverts when amount lesser than minimum acceptable amount is entered 
    error BuySellGENZ__LowAmountError();

    /// @notice reverts when user tries to withdraw token without purchasing GENZ token
    error BuyGENZ__ZeroTokensPurchasedError();

    /// @notice reverts when user is not having sufficient DAI ERC20 token to purchase GENZ token
    error BuySellGENZ__InsufficientBalanceError();

    /// @notice reverts when user tries to withdraw GENZ token before the minimum withdrawal time
    error BuyGENZ__EarlyWithdrawalRequestedError();
    

    
    // :::::::::::::::::::::::: CUSTOM EVENTS ::::::::::::::::::::::::::: //

    /// @notice emits after the contract has been initialized
    event InitializedContractBuyGENZ(address indexed adminAddress);

    /// @notice emits after the GENZ base sale price gets updated 
    event UpdatedBaseSalePrice(uint256 indexed updatedTokenPrice);

    /// @notice emits when the minimum withdrawal period time limit gets updated
    event UpdatedMinimumWithdrawalPeriod(uint256 indexed timeInDays);


    // :::::::::::::::::::::::::: FUNCTIONS ::::::::::::::::::::::::::::: //

    /// @dev this function faciliate users' to buy GENZ ERC20 token
    /// @param value: amount of GENZ ERC20 tokens user wishes to purchase
    /// @param deadline: DAI ERC20 token permit deadline
    /// @param permitV: DAI ERC20 token permit signature (value v)
    /// @param permitR: DAI ERC20 token permit signature (value r)
    /// @param permitS: DAI ERC20 token permit signature (value s)
    function buyGENZToken(
        uint256 value,
        uint deadline, 
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS
    ) external returns(bool);

    /// @dev this function aims to faciliate users' GENZ token withdrawal to their respcective wallets
    function withdrawTokens() external;

    
    // ::::::::::::::::::::::::: VIEW FUNCTIONS ::::::::::::::::::::::::: //

    /// @dev this function aims to calculate the current GENZ ERC20 token price
    /// @param issuedTokensGENZ: total number of GENZ ERC20 token issued to date
    /// @param requiredTokens: issuedTokensGENZ + amount of GENZ ERC20 user wishes to purchase
    function calculatePriceGENZ(
        uint256 issuedTokensGENZ, 
        uint256 requiredTokens
    ) external view returns(uint256, uint256);

    /// @dev this function aims to returns the token in circulation
    function getGENZTokenCount() external view returns(uint256);

    /// @dev this function aims to get the current GENZ ERC20 token price with decimals
    function getBasePriceWithDec() external view returns(uint256);

    /// @dev this function aims to get the current GENZ ERC20 token price
    function getCurrentTokenPrice() external view returns(uint256);


    // :::::::::::::::::::::::: END OF INTERFACE :::::::::::::::::::::::: //

}