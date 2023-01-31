// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/// @title AAVE Zero Premium Insurance Contract
/// @author Anshik Bansal <anshik@safezen.finance>

import "./AAVE.sol";
import "./../../../../interfaces/IERC20Extended.sol";

contract MockAAVE is AAVE {

    function mintERC20Tokens(address tokenAddress, uint256 amount) public {
        IERC20Extended(tokenAddress).mint(msg.sender, amount);
    }

}