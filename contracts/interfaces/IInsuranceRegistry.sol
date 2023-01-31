// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/// Report any bug or issues at:
/// @custom:security-contact anshik@safezen.finance
interface IInsuranceRegistry {

    error InsuranceRegistry__ImmutableChangesError();
    error InsuranceRegistry__TransactionFailedError();
    error InsuranceRegistry__NotEnoughLiquidityError();

    event UpdatedClaimStakedValue();

    function addInsuranceLiquidity(
        uint256 categoryID,
        uint256 subCategoryID_,
        uint256 liquiditySupplied
    ) external returns(bool);

    function removeInsuranceLiquidity(
        uint256 categoryID,
        uint256 subCategoryID_, 
        uint256 liquiditySupplied
    ) external returns(bool);

    function addCoverageOffered(
        uint256 categoryID,
        uint256 subCategoryID_, 
        uint256 coverageAmount,
        uint256 incomingFlowRate
    ) external returns(bool);

    function removeCoverageOffered(
        uint256 categoryID,
        uint256 subCategoryID_, 
        uint256 coverageAmount, 
        uint256 incomingFlowRate
    ) external returns(bool);

    function claimAdded(
        uint256 stakedTokenID, 
        uint256 categoryID, 
        uint256 subCategoryID_
    ) external returns(bool);

    function getVersionID(uint256 categoryID) external view returns(uint256);

    function calculateUnderwriterBalance(
        uint256 categoryID,
        uint256 subCategoryID_
    ) external view returns(uint256);

    function getLatestCategoryID() external view returns(uint256);

    function getLatestSubCategoryID(uint256 categoryID) external view returns(uint256);

    function ifEnoughLiquidity(uint256 categoryID, uint256 insuredAmount, uint256 subCategoryID_) external view returns(bool);

    function getStreamFlowRate(uint256 categoryID, uint256 subCategoryID_) external view returns(uint256);
}