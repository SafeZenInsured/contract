// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

interface ICoveragePool {

    // :::::::::::::::::::::::: CUSTOM ERROR CODE :::::::::::::::::::::::: //

    /// @notice reverts when user input wrong token ID which leads to zero address
    error CoveragePool__ZeroAddressInputError();

    /// @notice reverts when SZT Buy call gets failed.
    error CoveragePool__SZT_BuyOperationFailed();

    /// @notice reverts when SZT sell call gets failed.
    error CoveragePool__SZT_SellOperationFailed();

    /// @notice reverts when user is not having sufficient DAI ERC20 token to purchase GENZ token
    error CoveragePool__InsufficientBalanceError();

    /// @notice reverts when user tries to withdraw before withdrawal period \
    /// \or not have enough SZT balance to withdraw
    error CoveragePool__WithdrawalRestrictedError();

    /// @notice reverts when user input amount less than the minimum acceptable amount
    error CoveragePool__LessThanMinimumAmountError();

    error CoveragePool__InternalWithdrawOperationFailed();

    error CoveragePool__InternalUnderwriteOperationFailed();
    
    /// @notice reverts when add insurance liquidity call gets failed.
    error CoveragePool_AddInsuranceLiquidityOperationFailed();

    /// @notice reverts when remove insurance liquidity call gets failed.
    error CoveragePool_RemoveInsuranceLiquidityOperationFailed();
    
    // :::::::::::::::::::::::::: CUSTOM EVENTS :::::::::::::::::::::::::: //

    /// @notice emits after the SZT withdrawal waiting period time gets updated.
    event UpdatedWaitingPeriod(uint256 indexed timeInDays);

    /// @notice emits after the minimum coverage pool amount gets updated.
    event UpdatedMinCoveragePoolAmount(uint256 indexed valueInSZT);    

    /// @notice emits after the underwriter underwrite a coverage pool.
    /// @param userAddress: user wallet address
    /// @param categoryID: insurance category, e.g., stablecoin depeg insurance.
    /// @param subCategoryID: insurance sub-category, e.g., USDC depeg coverage, DAI depeg coverage.
    /// @param value: amount of SZT token 
    event UnderwritePool(
        address indexed userAddress, 
        uint256 categoryID, 
        uint256 subCategoryID, 
        uint256 indexed value
    );
    
    /// @notice emits after the underwriter withdraw the coverage offered in a coverage pool.
    /// @param userAddress: user wallet address
    /// @param categoryID: insurance category, e.g., stablecoin depeg insurance.
    /// @param subCategoryID: insurance sub-category, e.g., USDC depeg coverage, DAI depeg coverage.
    /// @param value: amount of SZT token 
    event PoolWithdrawn(
        address indexed userAddress, 
        uint256 categoryID, 
        uint256 subCategoryID, 
        uint256 indexed value
    );

    // :::::::::::::::::::::::: WRITING FUNCTIONS :::::::::::::::::::::::: //

    // :::::::::::::::::::::::: EXTERNAL FUNCTIONS ::::::::::::::::::::::: //

    function underwrite(
        uint256 tokenID,
        uint256 value, 
        uint256 categoryID, 
        uint256 subCategoryID,
        uint256 deadline, 
        uint8 permitV, 
        bytes32 permitR, 
        bytes32 permitS
    ) external returns(bool);

    function activateWithdrawalTimer(
        uint256 value, 
        uint256 categoryID, 
        uint256 subCategoryID
    ) external returns(bool);

    function withdraw(
        uint256 tokenID,
        uint256 value, 
        uint256 categoryID, 
        uint256 subCategoryID,
        uint256 deadline, 
        uint8 permitV, 
        bytes32 permitR, 
        bytes32 permitS
    ) external returns(bool);

    // :::::::::::::::::::::::: READING FUNCTIONS :::::::::::::::::::::::: //

    // ::::::::::::::::::: EXTERNAL PURE/VIEW FUNCTIONS :::::::::::::::::: //

    function totalTokensStaked() external view returns(uint256);

    function permissionedTokens(uint256 tokenID) external view returns(address);

    function userPoolBalanceSZT(address addressUser) external view returns(uint256);

    function getUserInfo(
        address addressUser,
        uint256 categoryID,
        uint256 subCategoryID
    ) external view returns(bool, uint256, uint256);

    function underwritersBalance(
        address addressUser,
        uint256 categoryID,
        uint256 subCategoryID,
        uint256 epoch
    ) external view returns(uint256);
}