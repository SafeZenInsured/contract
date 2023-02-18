// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IBuySellSZT {

    // ::::::::::::::::::::::: CUSTOM ERROR CODE :::::::::::::::::::::::: //

    /// @notice reverts when GSZT ERC20 token mint fails
    error BuySellSZT__MintFailedGSZT();

    /// @notice reverts when GSZT ERC20 token burn fails
    error BuySellSZT__BurnFailedGSZT();

    /// @notice reverts when the certain operation & functions has been paused.
    error BuySellSZT__OperationPaused();

    /// @notice reverts when the function access is restricted to only certain wallet or contract addresses.
    error BuySellSZT__AccessRestricted();

    /// @notice reverts when init function has already been initialized
    error BuySellSZT__InitializedEarlierError();

    /// @notice reverts when user input amount less than the minimum acceptable amount
    error BuySellSZT__LessThanMinimumAmountError();

    // :::::::::::::::::::::::: CUSTOM EVENTS ::::::::::::::::::::::::::: //

    /// @notice emits after the contract has been initialized
    event InitializedContractBuySellSZT(address indexed addressUser);

    /// @notice emits after the SZT token has been transferred to user
    /// @param addressUser: user wallet address
    /// @param amountInSZT: amount of SZT tokens user has purchased
    event BoughtSZT(
        address indexed addressUser,
        uint256 indexed amountInSZT
    );

    /// @notice emits after the SZT token has been transferred from user to contract
    /// @param addressUser: user wallet address
    /// @param amountInSZT: amount of SZT tokens user has sold
    event SoldSZT(
        address indexed addressUser,
        uint256 indexed amountInSZT
    );

    /// @notice emits after the GSZT token has been minted and transferred to user
    /// @param addressUser: user wallet address
    /// @param amountInGSZT: amount of minted GSZT ERC20 token
    event MintedGSZT(
        address indexed addressUser,
        uint256 indexed amountInGSZT
    );

    // ::::::::::::::::::::: EXTERNAL FUNCTIONS ::::::::::::::::::::::::: //

    /// @notice this function faciliate users' to buy SZT ERC20 non-speculative token
    /// @param addressUser: user wallet address
    /// @param amountInSZT: amount of SZT tokens user wishes to purchase
    function buyTokenSZT(
        address addressUser,
        uint256 amountInSZT
    ) external returns(bool);

    /// @notice this function faciliate users' sell SZT ERC20 token
    /// @param amountInSZT: amount of SZT tokens user wishes to sell
    /// @param deadline: GSZT ERC20 token permit deadline
    /// @param permitV: GSZT ERC20 token permit signature (value v)
    /// @param permitR: GSZT ERC20 token permit signature (value r)
    /// @param permitS: GSZT ERC20 token permit signature (value s)s
    function sellTokenSZT(
        address addressUser,
        uint256 amountInSZT,
        uint256 tokenID,
        uint256 deadline, 
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS
    ) external returns(bool);

    // ::::::::::::::::::::::::: VIEW FUNCTIONS ::::::::::::::::::::::::: //

    /// @notice this function aims to get the real time price of SZT ERC20 token
    function getRealTimePriceSZT() external view returns(uint256);

    /// @notice calculate the SZT token value for the asked amount of SZT tokens
    /// @param issuedTokensSZT: the amount of SZT tokens in circulation
    /// @param requiredTokens: issuedTokensSZT +  ERC20 SZT tokens user wishes to purchase
    function calculatePriceSZT(
        uint256 issuedTokensSZT, 
        uint256 requiredTokens
    ) external view returns(uint256, uint256);

    function tokenCounter() external view returns(uint256);
  
    // :::::::::::::::::::::::: END OF INTERFACE :::::::::::::::::::::::: //

}