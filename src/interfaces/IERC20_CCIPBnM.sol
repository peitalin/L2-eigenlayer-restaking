// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin-v5-contracts/token/ERC20/IERC20.sol";

interface IERC20_CCIPBnM is IERC20 {

    function drip(address to) external;
}