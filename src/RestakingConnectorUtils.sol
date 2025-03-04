// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Initializable} from "@openzeppelin-v5-contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin-v47-contracts/token/ERC20/IERC20.sol";
import {Client} from "@chainlink/ccip/libraries/Client.sol";
import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "@eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {ISignatureUtils} from "@eigenlayer-contracts/interfaces/ISignatureUtils.sol";

import {RestakingConnectorStorage} from "./RestakingConnectorStorage.sol";
import {FunctionSelectorDecoder} from "./utils/FunctionSelectorDecoder.sol";
import {EigenlayerMsgDecoders, DelegationDecoders} from "./utils/EigenlayerMsgDecoders.sol";
import {EigenlayerMsgEncoders} from "./utils/EigenlayerMsgEncoders.sol";

import {IRestakingConnector} from "./interfaces/IRestakingConnector.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {IAgentFactory} from "../src/6551/IAgentFactory.sol";


library RestakingConnectorUtils {

    function getEigenAgentBalancesWithdrawals(IEigenAgent6551 eigenAgent, IERC20[] memory tokensToWithdraw)
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

    function getEigenAgentBalancesRewards(
        IEigenAgent6551 eigenAgent,
        IRewardsCoordinator.RewardsMerkleClaim memory claim
    ) external view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](claim.tokenLeaves.length);
        for (uint256 i = 0; i < claim.tokenLeaves.length; ++i) {
            balances[i] = claim.tokenLeaves[i].token.balanceOf(address(eigenAgent));
        }
        return balances;
    }

}