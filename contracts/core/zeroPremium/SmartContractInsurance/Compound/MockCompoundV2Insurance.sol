// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "./CompoundV2Insurance.sol";
import "./../../../../interfaces/Compound/IErc20.sol";

contract MockCompoundV2Insurance is CompoundV2Insurance {

    event TokenMinted(
        address indexed userAddress, 
        address indexed tokenAddress, 
        uint256 amount
    );

    function mintERC20Tokens(address userAddress, address tokenAddress, uint256 amount) external {
        IErc20 token = IErc20(tokenAddress);
        token.allocateTo(userAddress, amount);
        emit TokenMinted(userAddress, tokenAddress, amount);
    }
}