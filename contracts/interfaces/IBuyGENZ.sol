// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IBuyGENZ {
    
    /// Custom Error Codes
    error BuySellGENZ__PausedError();
    error BuySellGENZ__LowAmountError();
    error BuySellGENZ__LowSZTBalanceError();
    error BuySellGENZ__GENZBurnFailedError();
    error BuySellGENZ__GENZMintFailedError();
    error BuySellGENZ__ImmutableChangesError();
    error BuySellGENZ__TransactionFailedError();
    error BuySellGENZ__ZeroAddressTransactionError();

}