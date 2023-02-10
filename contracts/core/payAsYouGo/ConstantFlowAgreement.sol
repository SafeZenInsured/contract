// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/// @title Constant Flow Agreement Contract
/// @author Anshik Bansal <anshik@safezen.finance>

/// Importing required interfaces
import "./../../interfaces/ICFA.sol";
import "./../../interfaces/IERC20Extended.sol";
import "./../../interfaces/IInsuranceRegistry.sol";

/// Importing required libraries
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

/// Importing required contracts
import "./../../BaseUpgradeablePausable.sol";

/// Report any bug or issues at:
/// @custom:security-contact anshik@safezen.finance

contract ConstantFlowAgreement is ICFA, BaseUpgradeablePausable {
    
    /// _categoriesCount: counter to keep track of the available insurance categories.
    /// _maxInsuredDays: the maximum insurance period [in days], 90 days will be kept as default.
    /// _startWaitingTime: insurance activation waiting period, 4-8 hours will be kept as default.
    /// _minimumInsurancePeriod: the minimum insurance period, 120 minutes will be kept as default.
    uint256 private _categoriesCount;
    uint256 private _maxInsuredDays;
    uint256 private _startWaitingTime;
    uint256 private _minimumInsurancePeriod;

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeERC20Upgradeable for IERC20PermitUpgradeable;

    /// _tokenDAI: DAI ERC20 token
    /// _SZTDAI: sztDAI ERC20 token
    /// _insuranceRegistry: Insurance Registry Contract
    IERC20Extended private _SZTDAI;
    IERC20Upgradeable private _tokenDAI;
    IERC20PermitUpgradeable private _tokenPermitSZTDAI;
    IInsuranceRegistry private _insuranceRegistry;

    /// @dev collects user information for particular insurance
    /// @param startTime: insurance activation time
    /// @param validTill: insurance validation till
    /// @param insuredAmount: maximum insurance amount covered
    /// @param insuranceFlowRate: amount to be charged per second [insurance flow rate * amount to be insured]
    /// @param insuranceCost: expected insurance premium cost for the registered duration
    /// @param registrationTime: insurance registration time
    /// @param isValid: checks whether user is an active insurance holder or not
    struct UserInsuranceInfo {
        uint256 startTime;
        uint256 validTill;
        uint256 insuredAmount;
        uint256 registrationTime;
        uint256 insuranceFlowRate;
        uint256 insuranceCost;
        bool isValid;
    }

    /// @dev collects user global insurance information
    /// @param validTill: expected insurance valid period
    /// @param insuranceStreamRate: global insurance flow rate per second
    /// @param globalInsuranceCost: expected global insurance premium cost for the registered duration
    struct UserGlobalInsuranceInfo {
        uint256 validTill;
        uint256 insuranceStreamRate;
        uint256 globalInsuranceCost;
    }

    /// @dev mapping to store UserGlobalInsuranceInfo
    /// maps: userAddress => UserGlobalInsuranceInfo
    mapping(address => UserGlobalInsuranceInfo) private usersGlobalInsuranceInfo;

    /// @dev mapping to store UserInsurance Info
    /// maps: userAddress => categoryID => subCategoryID => UserInsuranceInfo
    mapping(address => mapping(uint256 => mapping(uint256 => UserInsuranceInfo))) private usersInsuranceInfo;

    /// @dev one-time function aims to initialize the contract
    /// @dev MUST revert if called more than once.
    /// @param tokenDAIaddress: address of the DAI ERC20 token
    /// @param sztDAIAddress address of the sztDAI ERC20 token
    /// @param insuranceRegistryCA: address of the Protocol Registry contract
    /// @param minimumInsurancePeriod: minimum insurance period
    /// @return bool: true if the function executues successfully else false.
    /// [PRODUCTION TODO: _startWaitingTime =  startWaitingTime * 1 hours;]
    /// [PRODUCTION TODO: _maxInsuredDays = maxInsuredDays * 1 days;]
    function initialize(
        address tokenDAIaddress,
        address sztDAIAddress,
        address insuranceRegistryCA,
        uint256 minimumInsurancePeriod,
        uint256 startWaitingTime,
        uint256 maxInsuredDays
    ) external initializer returns(bool) {
        _categoriesCount = 0;
        _maxInsuredDays = maxInsuredDays * 1 minutes;
        _startWaitingTime = startWaitingTime * 1 minutes; 
        _minimumInsurancePeriod = minimumInsurancePeriod * 1 minutes;
        _tokenDAI = IERC20Upgradeable(tokenDAIaddress);
        _SZTDAI = IERC20Extended(sztDAIAddress);
        _tokenPermitSZTDAI = IERC20PermitUpgradeable(tokenDAIaddress);
        _insuranceRegistry = IInsuranceRegistry(insuranceRegistryCA);
        __BaseUpgradeablePausable_init(_msgSender());
        return true;
    }

    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }

    /// @dev this function aims to updates minimum insurance period
    /// @param timeInMinutes: 120 minutes will be kept as default.
    function updateMinimumInsurancePeriod(uint256 timeInMinutes) external onlyAdmin {
        _minimumInsurancePeriod = timeInMinutes * 1 minutes;
        emit UpdatedMinimumInsurancePeriod();
    }

    /// @dev this function aims to update the insurance activation waiting period
    /// @param timeInHours: 4-8 hours will be kept as default. 
    function updateStartWaitingTime(uint256 timeInHours) external onlyAdmin {
        _startWaitingTime = timeInHours * 1 hours;
        emit UpdatedStartWaitingTime();
    }

    /// @dev this function aims to update the maximum insurance period
    /// @param timeInDays: 90 days will be kept as default.
    function updateMaxInsuredDays(uint256 timeInDays) external onlyAdmin {
        _maxInsuredDays = timeInDays * 1 days;
        emit UpdatedMaxInsuredDays();
    }

    /// @dev this function aims to create or top-up user insurance coverage amount.
    /// @param insuredAmount: maximum user coverage amount
    /// @param categoryID: insurance category, e.g., stablecoin depeg insurance.
    /// @param subCategoryID: insurance sub-category, e.g., USDC depeg coverage, DAI depeg coverage.
    /// @return bool: true if the function executues successfully else false.
    function addInsuranceAmount(
        uint256 insuredAmount, 
        uint256 categoryID, 
        uint256 subCategoryID, 
        uint256 deadline,
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external override nonReentrant returns(bool) {
        uint256 minDeadlinePeriod = block.timestamp + _maxInsuredDays + 30 days; 
        if(deadline < minDeadlinePeriod) {
            revert CFA__TransactionFailedError();
        }
        bool success = _addInsuranceAmount(insuredAmount, categoryID, subCategoryID, deadline, v, r, s);
        return success;
    }
    
    
    function _addInsuranceAmount(
        uint256 insuredAmount, 
        uint256 categoryID, 
        uint256 subCategoryID,
        uint256 deadline,
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) private returns(bool) {
        uint256 newInsuredAmount = usersInsuranceInfo[_msgSender()][categoryID][subCategoryID].insuredAmount + insuredAmount;
        if (usersInsuranceInfo[_msgSender()][categoryID][subCategoryID].isValid) {
            bool closeStreamSuccess = deactivateInsurance(_msgSender(), categoryID, subCategoryID);
            if (!closeStreamSuccess) {
                revert CFA__TransactionFailedError();
            }
        }   
         
        (bool activateSuccess, uint256 insuranceCost) = activateInsurance(newInsuredAmount, categoryID, subCategoryID);
        if (!activateSuccess) {
            revert CFA__TransactionFailedError();
        }
        _tokenPermitSZTDAI.safePermit(_msgSender(), address(this), insuranceCost, deadline, v, r, s);  
        return true;
    }

    /// @dev this function aims to close or reduce user insurance coverage amount.
    /// @param insuredAmount: maximum user coverage amount
    /// @param categoryID: insurance category, e.g., stablecoin depeg insurance.
    /// @param subCategoryID: insurance sub-category, e.g., USDC depeg coverage, DAI depeg coverage.
    /// @param closeStream: checks whether user initiate to deactivate its insurance or not.
    /// @return bool: true if the function executues successfully else false.
    function minusInsuranceAmount(
        uint256 insuredAmount, 
        uint256 categoryID, 
        uint256 subCategoryID,
        uint256 deadline,
        uint8 v, 
        bytes32 r, 
        bytes32 s,
        bool closeStream
    ) external override nonReentrant returns(bool) {
        uint256 minDeadlinePeriod = block.timestamp + _maxInsuredDays + 30 days; 
        if(deadline < minDeadlinePeriod) {
            revert CFA__TransactionFailedError();
        }
        bool success = _minusInsuranceAmount(insuredAmount, categoryID, subCategoryID, deadline, v, r, s, closeStream);
        return success;
    }
    
    
    function _minusInsuranceAmount(
        uint256 insuredAmount, 
        uint256 categoryID, 
        uint256 subCategoryID,
        uint256 deadline,
        uint8 v, 
        bytes32 r, 
        bytes32 s,
        bool closeStream
    ) private returns(bool) {
        if (!usersInsuranceInfo[_msgSender()][categoryID][subCategoryID].isValid) {
            revert CFA__InactiveInsuranceError();
        }
        bool closeStreamSuccess = deactivateInsurance(_msgSender(), categoryID, subCategoryID);
        if (!closeStreamSuccess) {
            revert CFA__TransactionFailedError();
        }
        if (!closeStream) {
            uint256 newInsuredAmount = usersInsuranceInfo[_msgSender()][categoryID][subCategoryID].insuredAmount - insuredAmount;
            (bool activateSuccess, uint256 insuranceCost) = activateInsurance(newInsuredAmount, categoryID, subCategoryID);
            if (!activateSuccess) {
                revert CFA__TransactionFailedError();
            }
            _tokenPermitSZTDAI.safePermit(_msgSender(), address(this), insuranceCost, deadline, v, r, s);  

        }
        return true;
    }

    function claimPremium(
        address userAddress,
        uint256 categoryID,
        uint256 subCategoryID
    ) external returns(bool) {
        if (
            getUserInsuranceValidTillInfo(userAddress, categoryID, subCategoryID) > 
            block.timestamp
        ) {
            revert CFA__ActiveInsuranceExistError();
        }
        bool success = deactivateInsurance(userAddress, categoryID, subCategoryID);
        if (!success) {
            revert CFA__TransactionFailedError();
        }
        return true;
    }

    function claimPremium(
        address userAddress,
        uint256 categoryID
    ) external returns(bool) {

    }

    /// @param insuredAmount: insured amount
    /// @param categoryID: like Smart Contract Insurance
    function activateInsurance(
        uint256 insuredAmount,
        uint256 categoryID,
        uint256 subCategoryID
    ) private returns(bool, uint256) {
        if (insuredAmount < 1e18) {
            revert CFA__InsuranceCoverNotAvailableError();
        }
        if (
            (!_insuranceRegistry.ifEnoughLiquidity(categoryID, insuredAmount, subCategoryID))    
        ) {
            revert CFA__SubCategoryNotActiveError();
        }
        if (usersInsuranceInfo[_msgSender()][categoryID][subCategoryID].isValid) {
            revert CFA__ActiveInsuranceExistError();
        }
        
        UserInsuranceInfo storage userInsuranceInfo = usersInsuranceInfo[_msgSender()][categoryID][subCategoryID];
        UserGlobalInsuranceInfo storage userGlobalInsuranceInfo = usersGlobalInsuranceInfo[_msgSender()];
        
        uint256 userEstimatedBalance = _SZTDAI.balanceOf(_msgSender()) - userGlobalInsuranceInfo.globalInsuranceCost;
        uint256 incomingAmountPerSec = (
            _insuranceRegistry.getStreamFlowRate(categoryID, subCategoryID) * insuredAmount) / 1e18;
        uint256 globalIncomingAmountPerSec = userGlobalInsuranceInfo.insuranceStreamRate + incomingAmountPerSec;
        // user balance should be enough to run the insurance for atleast minimum insurance time duration
        if ((globalIncomingAmountPerSec * _minimumInsurancePeriod) > userEstimatedBalance) {
            revert CFA__NotEvenMinimumInsurancePeriodAmount();
        }

        uint256 validTill = (userEstimatedBalance / incomingAmountPerSec);
        userGlobalInsuranceInfo.insuranceStreamRate += incomingAmountPerSec;
        userInsuranceInfo.insuredAmount = insuredAmount;
        userInsuranceInfo.insuranceFlowRate = incomingAmountPerSec;
        userInsuranceInfo.registrationTime = block.timestamp;
        userInsuranceInfo.startTime = block.timestamp + _startWaitingTime;
        userInsuranceInfo.validTill = (
            validTill < _maxInsuredDays ? 
            userInsuranceInfo.startTime + validTill : userInsuranceInfo.startTime + _maxInsuredDays
        );
        userInsuranceInfo.insuranceCost = validTill * incomingAmountPerSec;
        userInsuranceInfo.isValid = true;
        
        userGlobalInsuranceInfo.globalInsuranceCost += userInsuranceInfo.insuranceCost;
        userGlobalInsuranceInfo.validTill = (
            userInsuranceInfo.validTill < userGlobalInsuranceInfo.validTill ? 
            userGlobalInsuranceInfo.validTill : userInsuranceInfo.validTill
        );
        bool success = _insuranceRegistry.addCoverageOffered(categoryID, subCategoryID, insuredAmount, incomingAmountPerSec);
        return (success, userInsuranceInfo.insuranceCost);
    }

    /// @notice this function aims to return the expected insurance cost and deadline for respective insurances
    /// @param insuredAmount: maximum user coverage amount
    /// @param categoryID: insurance category, e.g., stablecoin depeg insurance.
    /// @param subCategoryID: insurance sub-category, e.g., USDC depeg coverage, DAI depeg coverage.
    function getExpectedInsuranceCostAndDeadline(
        uint256 insuredAmount,
        uint256 categoryID,
        uint256 subCategoryID
    ) external view returns(uint256, uint256) {
        UserGlobalInsuranceInfo memory userGlobalInsuranceInfo = usersGlobalInsuranceInfo[_msgSender()];
        
        uint256 userEstimatedBalance = _SZTDAI.balanceOf(_msgSender()) - userGlobalInsuranceInfo.globalInsuranceCost;
        uint256 incomingAmountPerSec = (
            _insuranceRegistry.getStreamFlowRate(categoryID, subCategoryID) * insuredAmount) / 1e18;
        
        uint256 expectedValidTill = (userEstimatedBalance / incomingAmountPerSec);
        uint256 validTill =  (
            expectedValidTill < _maxInsuredDays ? 
            (block.timestamp + _startWaitingTime) + expectedValidTill : 
            (block.timestamp + _startWaitingTime) + _maxInsuredDays
        );
        uint256 insuranceCost = validTill * incomingAmountPerSec;
        uint256 deadline = block.timestamp + _maxInsuredDays + 30 days;
        return (insuranceCost, deadline);
    }

    /// NOTE: few if and else to consider for globalinsuranceinfo like endtime and start time 
    /// [FORGOT IT, WHAT IT MEANS, BUT NEED TO CHECK]
    /// @param userAddress: user wallet address
    /// @param categoryID: insurance category, e.g., stablecoin depeg insurance.
    /// @param subCategoryID: insurance sub-category, e.g., USDC depeg coverage, DAI depeg coverage.
    function deactivateInsurance(
        address userAddress, 
        uint256 categoryID, 
        uint256 subCategoryID
    ) private returns(bool) {
        UserInsuranceInfo storage userInsuranceInfo = usersInsuranceInfo[userAddress][categoryID][subCategoryID];
        if (!userInsuranceInfo.isValid) {
            revert CFA__InactiveInsuranceError();
        }
        userInsuranceInfo.isValid = false;
        uint256 duration = (
            (block.timestamp > userInsuranceInfo.startTime) ? (
                (block.timestamp > userInsuranceInfo.validTill) ? 
                userInsuranceInfo.validTill : (block.timestamp - userInsuranceInfo.startTime)
            ) : 0);
        uint256 amountToBeBurned = (duration * userInsuranceInfo.insuranceFlowRate);
        if (amountToBeBurned == 0) {
            return true;
        } 
        usersGlobalInsuranceInfo[userAddress].insuranceStreamRate -= userInsuranceInfo.insuranceFlowRate;
        usersGlobalInsuranceInfo[userAddress].globalInsuranceCost -= userInsuranceInfo.insuranceCost;
        uint256 flowRate = userInsuranceInfo.insuranceFlowRate;
        uint256 insuredAmount = userInsuranceInfo.insuredAmount;
        bool success = _insuranceRegistry.removeCoverageOffered(categoryID, subCategoryID, insuredAmount, flowRate);
        bool burnSuccess = _SZTDAI.burnFrom(userAddress, amountToBeBurned);
        if ((!success) || (!burnSuccess)) {
            revert CFA__TransactionFailedError();
        }
        return true;
    }

    /// @dev this function aims to deactivate user's all activated insurance in a single-call.
    /// @param userAddress: user wallet address
    /// @param categoryID: insurance category, e.g., stablecoin depeg insurance.
    function deactivateCategoryInsurance(
        address userAddress, 
        uint256 categoryID
    ) private returns(bool) {
        uint256[] memory activeID = findActivePremiumCost(userAddress, categoryID, _insuranceRegistry.getLatestSubCategoryID(categoryID));
        uint256 expectedAmountToBePaid = _calculateTotalFlowMade(userAddress, categoryID, activeID);
        for(uint256 i=0; i < activeID.length;) {
            usersInsuranceInfo[userAddress][categoryID][activeID[i]].isValid = false;
            uint256 flowRate = usersInsuranceInfo[userAddress][categoryID][activeID[i]].insuranceFlowRate;
            uint256 insuredAmount = usersInsuranceInfo[userAddress][categoryID][activeID[i]].insuredAmount;
            bool coverageRemoveSuccess = _insuranceRegistry.removeCoverageOffered(categoryID, activeID[i], insuredAmount, flowRate);
            if (!coverageRemoveSuccess) {
                revert CFA__TransactionFailedError();
            }
            ++i;
        }
        uint256 userBalance = _SZTDAI.balanceOf(userAddress); 
        uint256 amountToBeBurned = expectedAmountToBePaid > userBalance ? userBalance : expectedAmountToBePaid;
        usersGlobalInsuranceInfo[userAddress].insuranceStreamRate = 0;
        bool success = _SZTDAI.burnFrom(userAddress, amountToBeBurned);
        if (!success) {
            revert CFA__TransactionFailedError();
        }
        return true;
    }

    /// VIEW FUNCTIONS

    function findActivePremiumCost(
        address userAddress, 
        uint256 categoryID, 
        uint256 subCategoryCount
    ) public view override returns(uint256[] memory) {
        uint256 activeProtocolCount = 0;
        for(uint i = 0; i < subCategoryCount;) {
            UserInsuranceInfo memory userInsuranceInfo = usersInsuranceInfo[userAddress][categoryID][i];
            if (userInsuranceInfo.isValid) {
                ++activeProtocolCount;
            }
            ++i;
        }
        uint256[] memory activeID = new uint256[](activeProtocolCount);
        uint256 counter = 0;
        for(uint i = 0; i < subCategoryCount;) {
            UserInsuranceInfo storage userInsuranceInfo = usersInsuranceInfo[userAddress][categoryID][i];
            if (userInsuranceInfo.isValid) {
                activeID[counter] = i;
                ++counter;
            }
            ++i;
        }
      return activeID;
    }

    /// DURATION
    function calculateTotalFlowMade(
        address userAddress
    ) external view returns(uint256) {
        uint256 globalBalanceToBePaid = 0;
        for(uint256 i=0; i < _categoriesCount;) {
            uint256 balanceToBePaid = 0;
            uint256[] memory activeID = findActivePremiumCost(userAddress, i, _insuranceRegistry.getLatestSubCategoryID(i));
            for(uint256 j=0; j < activeID.length;) {
                UserInsuranceInfo storage userActiveInsuranceInfo = usersInsuranceInfo[userAddress][i][activeID[j]];
                uint256 duration = (
                    (block.timestamp > userActiveInsuranceInfo.startTime) ? (
                        (block.timestamp > userActiveInsuranceInfo.validTill) ? 
                        userActiveInsuranceInfo.validTill : (block.timestamp - userActiveInsuranceInfo.startTime)
                    ) : 0);
                balanceToBePaid += (userActiveInsuranceInfo.insuranceFlowRate * duration);
                ++j;
            }
            globalBalanceToBePaid += balanceToBePaid;
            ++i;
        }
        return globalBalanceToBePaid;
    }

    function _calculateTotalFlowMade(
        address userAddress, 
        uint256 categoryID,
        uint256[] memory activeID
    ) internal view returns(uint256) {
        uint256 balanceToBePaid = 0;
        for(uint256 i=0; i< activeID.length;){
            UserInsuranceInfo storage userActiveInsuranceInfo = usersInsuranceInfo[userAddress][categoryID][activeID[i]];
            uint256 duration = (
                (block.timestamp > userActiveInsuranceInfo.startTime) ? (
                    (block.timestamp > userActiveInsuranceInfo.validTill) ? 
                    userActiveInsuranceInfo.validTill : (block.timestamp - userActiveInsuranceInfo.startTime)
                ) : 0);
            balanceToBePaid += (userActiveInsuranceInfo.insuranceFlowRate * duration);
            ++i;
        }
        return balanceToBePaid;
    }

    /// DURATION
    function calculateTotalFlowMade(
        address userAddress, 
        uint256 categoryID
    ) external view override returns(uint256) {
        uint256 balanceToBePaid = 0;
        uint256[] memory activeID = findActivePremiumCost(userAddress, categoryID, _insuranceRegistry.getLatestSubCategoryID(categoryID));
        for(uint256 i=0; i< activeID.length;){
            UserInsuranceInfo storage userActiveInsuranceInfo = usersInsuranceInfo[userAddress][categoryID][activeID[i]];
            uint256 duration = (
                (block.timestamp > userActiveInsuranceInfo.startTime) ? (
                    (block.timestamp > userActiveInsuranceInfo.validTill) ? 
                    userActiveInsuranceInfo.validTill : (block.timestamp - userActiveInsuranceInfo.startTime)
                ) : 0);
            balanceToBePaid += (userActiveInsuranceInfo.insuranceFlowRate * duration);
            ++i;
        }
        return balanceToBePaid;
    } 

    function getUserInsuranceValidTillInfo(
        address userAddress, 
        uint256 categoryID, 
        uint256 subCategoryID
    ) public view override returns(uint256) {
        return usersInsuranceInfo[userAddress][categoryID][subCategoryID].validTill;
    }

    function getUserInsuranceStatus(
        address userAddress, 
        uint256 categoryID, 
        uint256 subCategoryID
    ) external view override returns(bool) {
        return usersInsuranceInfo[userAddress][categoryID][subCategoryID].isValid;
    }

    function getUserInsuranceInfo(
        address userAddress, 
        uint256 categoryID, 
        uint256 subCategoryID
    ) external view override returns(uint256, uint256, uint256, uint256, uint256, bool) {
        UserInsuranceInfo memory userInsuranceInfo = usersInsuranceInfo[userAddress][categoryID][subCategoryID];
        return (
            userInsuranceInfo.insuredAmount, 
            userInsuranceInfo.insuranceFlowRate,
            userInsuranceInfo.registrationTime,
            userInsuranceInfo.startTime,
            userInsuranceInfo.validTill,
            userInsuranceInfo.isValid
            );
    }

    function getGlobalUserInsuranceInfo(
        address _userAddress
    ) external view override returns (uint256, uint256) {
        UserGlobalInsuranceInfo memory userGlobalInsuranceInfo = usersGlobalInsuranceInfo[_userAddress];
        return (userGlobalInsuranceInfo.insuranceStreamRate, userGlobalInsuranceInfo.validTill);
    }

    function getGlobalUserInsurancePremiumCost(
        address userAddress
    ) external view override returns(uint256) {
       UserGlobalInsuranceInfo memory userGlobalInsuranceInfo = usersGlobalInsuranceInfo[userAddress];
        return userGlobalInsuranceInfo.globalInsuranceCost; 
    }

    function getUserInsuredAmount(
        address userAddress, 
        uint256 categoryID, 
        uint256 subCategoryID
    ) external view returns(uint256) {
        return usersInsuranceInfo[userAddress][categoryID][subCategoryID].insuredAmount;
    }
}