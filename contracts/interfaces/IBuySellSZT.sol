// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IBuySellSZT {

    error BuySellSZT__PausedError();
    error BuySellSZT__LowAmountError();
    error BuySellSZT__LowSZTBalanceError();
    error BuySellSZT__GSZTBurnFailedError();
    error BuySellSZT__ImmutableChangesError();
    error BuySellSZT__TransactionFailedError();
    error BuySellSZT__ZeroAddressTransactionError();
    error BuySellSZT_sellSZTToken__TxnFailedError();
    error BuySellSZT_mintGSZT__MintFailedError(); 
    
    event BoughtSZT(address indexed userAddress, uint256 value);

    event SoldSZT(address indexed userAddress, uint256 value);

    event GSZTMint(address indexed userAddress, uint256 value);

    event GSZTBurn(address indexed userAddress, uint256 value);

    event TransferredSZT(address indexed from, address indexed to, uint256 value);

    event GSZTOwnershipTransferred(
        address indexed investorAddress, 
        address indexed newInvestorAddress, 
        uint256 value
    );

    function viewSZTCurrentPrice() view external returns(uint);

    function buySZTToken(
        address userAddress,
        uint256 _value
    ) external returns(bool);

    function sellSZTToken(
        address userAddress,
        uint256 value,
        uint256 deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external returns(bool);

    function getTokenCounter() external view returns(uint256);

    function calculatePriceSZT(
        uint256 issuedSZTTokens, 
        uint256 requiredTokens
    ) view external returns(uint, uint);
}