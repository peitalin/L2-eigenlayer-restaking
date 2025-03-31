// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Adminable} from "./Adminable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Faucet is Adminable {
    IERC20 public token;
    uint256 public maxLimitPerUser;
    mapping(address => uint256) public userClaims;

    event TokenSet(address indexed token);
    event MaxLimitSet(uint256 maxLimit);
    event TokensClaimed(address indexed user, uint256 amount);
    event TokensWithdrawn(address indexed admin, uint256 amount);

    error InvalidTokenAddress();
    error InvalidMaxLimit();
    error ClaimLimitExceeded();
    error InsufficientFaucetBalance();

    constructor() {
        _disableInitializers();
    }

    function initialize(address _token, uint256 _maxLimitPerUser) external initializer {
        __Adminable_init();
        _setToken(_token);
        _setMaxLimit(_maxLimitPerUser);
    }

    function claim(uint256 amount) external {
        if (userClaims[msg.sender] + amount > maxLimitPerUser) {
            revert ClaimLimitExceeded();
        }
        if (token.balanceOf(address(this)) < amount) {
            revert InsufficientFaucetBalance();
        }

        userClaims[msg.sender] += amount;
        token.transfer(msg.sender, amount);
        emit TokensClaimed(msg.sender, amount);
    }

    function setToken(address _token) external onlyAdminOrOwner {
        _setToken(_token);
    }

    function setMaxLimit(uint256 _maxLimitPerUser) external onlyAdminOrOwner {
        _setMaxLimit(_maxLimitPerUser);
    }

    function withdrawTokens(uint256 amount) external onlyAdminOrOwner {
        if (token.balanceOf(address(this)) < amount) {
            revert InsufficientFaucetBalance();
        }
        token.transfer(msg.sender, amount);
        emit TokensWithdrawn(msg.sender, amount);
    }

    function _setToken(address _token) private {
        if (_token == address(0)) {
            revert InvalidTokenAddress();
        }
        token = IERC20(_token);
        emit TokenSet(_token);
    }

    function _setMaxLimit(uint256 _maxLimitPerUser) private {
        if (_maxLimitPerUser == 0) {
            revert InvalidMaxLimit();
        }
        maxLimitPerUser = _maxLimitPerUser;
        emit MaxLimitSet(_maxLimitPerUser);
    }
}
