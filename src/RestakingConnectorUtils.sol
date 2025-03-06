// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin-v47-contracts/token/ERC20/IERC20.sol";
import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";


library RestakingConnectorUtils {

    function getEigenAgentBalances(IEigenAgent6551 eigenAgent, IERC20[] memory tokensToWithdraw)
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory balances = new uint256[](tokensToWithdraw.length);
        for (uint256 i = 0; i < tokensToWithdraw.length; ++i) {
            balances[i] = tokensToWithdraw[i].balanceOf(address(eigenAgent));
        }
        return balances;
    }

   /**
     * @notice Filters an array of IRewardsCoordinator.TokenTreeMerkleLeaf to return only unique tokens
     * @param tokenLeaves Array of IRewardsCoordinator.TokenTreeMerkleLeaf structs
     * @return uniqueTokens A new array containing only unique IERC20 tokens
     */
    function getUniqueTokens(IRewardsCoordinator.TokenTreeMerkleLeaf[] memory tokenLeaves)
        external
        pure
        returns (IERC20[] memory uniqueTokens)
    {
        if (tokenLeaves.length == 0) return new IERC20[](0);
        if (tokenLeaves.length == 1) {
            IERC20[] memory uniqueArray = new IERC20[](1);
            uniqueArray[0] = tokenLeaves[0].token;
            return uniqueArray;
        }

        // Create a temporary array to store unique tokens
        IERC20[] memory tempUnique = new IERC20[](tokenLeaves.length);
        uint256 uniqueCount = 0;

        // For each token, check if we've seen it before in our result array
        for (uint256 i = 0; i < tokenLeaves.length; i++) {
            bool isDuplicate = false;
            address currentToken = address(tokenLeaves[i].token);

            // Check if this token is already in our temp array
            for (uint256 j = 0; j < uniqueCount; j++) {
                if (address(tempUnique[j]) == currentToken) {
                    isDuplicate = true;
                    break;
                }
            }

            // If not a duplicate, add to our temp array
            if (!isDuplicate) {
                tempUnique[uniqueCount] = tokenLeaves[i].token;
                uniqueCount++;
            }
        }

        // Create final array with exact size needed
        uniqueTokens = new IERC20[](uniqueCount);
        for (uint256 i = 0; i < uniqueCount; i++) {
            uniqueTokens[i] = tempUnique[i];
        }

        return uniqueTokens;
    }

   /**
     * @notice Filters an array of tokens to return only unique tokens
     * @param tokens Array of IERC20 token interfaces
     * @return uniqueTokens A new array containing only unique tokens
     */
    function getUniqueTokens(IERC20[] memory tokens)
        external
        pure
        returns (IERC20[] memory uniqueTokens)
    {
        if (tokens.length == 0) return new IERC20[](0);
        if (tokens.length == 1) return tokens;

        // Create a temporary array to store unique tokens
        IERC20[] memory tempUnique = new IERC20[](tokens.length);
        uint256 uniqueCount = 0;

        // For each token, check if we've seen it before in our result array
        for (uint256 i = 0; i < tokens.length; i++) {
            bool isDuplicate = false;
            address currentToken = address(tokens[i]);

            // Check if this token is already in our temp array
            for (uint256 j = 0; j < uniqueCount; j++) {
                if (address(tempUnique[j]) == currentToken) {
                    isDuplicate = true;
                    break;
                }
            }

            // If not a duplicate, add to our temp array
            if (!isDuplicate) {
                tempUnique[uniqueCount] = tokens[i];
                uniqueCount++;
            }
        }

        // Create final array with exact size needed
        uniqueTokens = new IERC20[](uniqueCount);
        for (uint256 i = 0; i < uniqueCount; i++) {
            uniqueTokens[i] = tempUnique[i];
        }

        return uniqueTokens;
    }
}

