// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/// Report any bug or issues at:
/// @custom:security-contact anshik@safezen.finance
interface IInsuranceRegistry {

    error InsuranceRegistry__AccessRestricted();

    event InsuranceProductAdded();

    function epoch(uint256 categoryID) external view returns(uint256);

    function epochRiskPoolCategory(uint256 categoryID, uint256 subCategoryID, uint256 epoch) external view returns(uint256);

    function subCategoryID(uint256 categoryID) external view returns(uint256);

    function getVersionableRiskPoolsInfo(
        uint256 categoryID, 
        uint256 riskPoolCategory, 
        uint256 epoch
    ) external view returns(
        uint256 startTime, 
        uint256 endTime, 
        uint256 riskPoolLiquidity, 
        uint256 riskPoolStreamRate, 
        uint256 liquidation
    );

    function calculateUnderwriterBalance(
        uint256 categoryID,
        uint256 subCategoryID
    ) external view returns(uint256);

    function categoryID() external view returns(uint256);




    
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
        uint256 categoryID, 
        uint256 subCategoryID_
    ) external returns(bool);

    function getVersionID(uint256 categoryID) external view returns(uint256);

    function getLatestCategoryID() external view returns(uint256);

    function getLatestSubCategoryID(uint256 categoryID) external view returns(uint256);

    function ifEnoughLiquidity(uint256 categoryID, uint256 insuredAmount, uint256 subCategoryID_) external view returns(bool);

    function getStreamFlowRate(uint256 categoryID, uint256 subCategoryID_) external view returns(uint256);
}