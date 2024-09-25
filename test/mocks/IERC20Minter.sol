// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC20Minter is IERC20 {

    function mint(address to, uint256 amount) external;

    function burn(address from, uint256 amount) external;
}