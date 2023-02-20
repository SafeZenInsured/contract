// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;


interface ICFA {
    
    
    error CFA__OperationPaused();
    
    error CFA__InsufficientBalanceError();

    error CFA__StableSZT_BurnOperationFailed();

    error CFA__RemoveCoverageOperationFailed();

    error CFA__DeactivateInsuranceOperationFailed();
    
    
    
    // CFA Custom Error Code
    error CFA__ImmutableChangesError();
    error CFA__TransactionFailedError();
    error CFA__InactiveInsuranceError();
    error CFA__SubCategoryNotActiveError();
    error CFA__ActiveInsuranceExistError();
    error CFA__InsuranceCoverNotAvailableError();
    error CFA__NotEvenMinimumInsurancePeriodAmount();
    
    
    // CFA Events
    event UpdatedMaxInsuredDays();
    event UpdatedStartWaitingTime();
    event UpdatedMinimumInsurancePeriod();

    

    function addInsuranceAmount(
        uint256 insuredAmount, 
        uint256 categoryID, 
        uint256 subCategoryID,
        uint256 deadline,
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external returns(bool);

    function minusInsuranceAmount(
        uint256 insuredAmount, 
        uint256 categoryID, 
        uint256 subCategoryID,
        uint256 deadline,
        uint8 v, 
        bytes32 r, 
        bytes32 s,
        bool closeStream
    ) external returns(bool);

    function findActivePremiumCost(
        address userAddress, 
        uint256 categoryID, 
        uint256 insuranceCount
    ) external view returns(uint256[] memory);

    function calculateTotalFlowMade(
        address userAddress, 
        uint256 categoryID
    ) external view returns(uint256);  

    function calculateTotalFlowMade(
        address userAddress
    ) external view returns(uint256); 

    function getUserInsuranceValidTillInfo(
        address userAddress, 
        uint256 categoryID, 
        uint256 subCategoryID
    ) external view returns(uint256);

    function getUserInsuranceStatus(
        address userAddress, 
        uint256 categoryID, 
        uint256 subCategoryID
    ) external view returns(bool);

    function getUserInsuranceInfo(
        address userAddress, 
        uint256 categoryID, 
        uint256 subCategoryID
    ) external view returns(uint256, uint256, uint256, uint256, uint256, bool);
    
    function getGlobalUserInsuranceInfo(
        address _userAddress
    ) external view returns (uint256, uint256);

    function getGlobalUserInsurancePremiumCost(
        address userAddress
    ) external view returns(uint256);

    function getExpectedInsuranceCostAndDeadline(
        uint256 insuredAmount,
        uint256 categoryID,
        uint256 subCategoryID
    ) external view returns(uint256, uint256);
}