// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

interface ICoveragePool {

    error CoveragePool__ImmutableChangesError();
    error CoveragePool__TransactionFailedError();
    error CoveragePool__NotAMinimumPoolAmountError();
    error CoveragePool__LowAmountError();
    
    event UpdatedMinCoveragePoolAmount();
    event UpdatedWaitingPeriod(uint256 indexed timeInDays);
    event UnderwritePool(
        address indexed userAddress, 
        uint256 categoryID, 
        uint256 subCategoryID, 
        uint256 indexed value
    );
    event PoolWithdrawn(
        address indexed userAddress, 
        uint256 categoryID, 
        uint256 subCategoryID, 
        uint256 indexed value
    );

    function totalTokensStaked() external view returns(uint256);

    function underwrite(
        uint256 value, 
        uint256 categoryID, 
        uint256 subCategoryID,
        uint deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external returns(bool);

    function activateWithdrawalTimer(
        uint256 value, 
        uint256 categoryID, 
        uint256 subCategoryID
    ) external returns(bool);

    function withdraw(
        uint256 value, 
        uint256 categoryID, 
        uint256 subCategoryID,
        uint256 deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external returns(bool);

    function getUnderwriteSZTBalance(
        address userAddress
    ) external view returns(uint256);

    function getUnderwriterActiveVersionID(
        uint256 categoryID, 
        uint256 subCategoryID
    ) external view returns(uint256[] memory);

    function getUnderWriterDepositedBalance(
        uint256 categoryID, 
        uint256 subCategoryID, 
        uint256 version
    ) external view returns(uint256);

    function getUnderWriterWithdrawnBalance(
        uint256 categoryID, 
        uint256 subCategoryID, 
        uint256 version
    ) external view returns(uint256);
}