// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {IRewardsCoordinatorTypes} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {Client} from "@chainlink/ccip/libraries/Client.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";

import {BaseScript} from "./BaseScript.sol";
import {EthSepolia} from "./Addresses.sol";
import {RewardsUtils, TestRewardsTree} from "./RewardsUtils.sol";
import {
    REWARDS_AMOUNT_1,
    REWARDS_AMOUNT_2,
    REWARDS_AMOUNT_3,
    REWARDS_AMOUNT_4
} from "./9_submitRewards.s.sol";


contract ProcessClaimRewardsScript is BaseScript, RewardsUtils {

    uint256 deployerKey;
    address deployer;

    address TARGET_CONTRACT; // Contract that EigenAgent forwards calls to
    uint256 execNonce; // EigenAgent execution nonce
    uint256 expiry;
    IEigenAgent6551 eigenAgent;

    address[4] EARNERS;
    uint256[4] REWARDS_AMOUNTS;

    mapping(address => uint32) public earnerIndexes;

    function run() public {
        return _run(false);
    }

    function mockrun() public {
        return _run(true);
    }

    function _run(bool isTest) private {

        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);
        readContractsAndSetupEnvironment(isTest, deployer);

        TARGET_CONTRACT = address(rewardsCoordinator);

        /////////////////////////////////////////////////////////////////
        ////// L1: Get Complete Withdrawals Params
        /////////////////////////////////////////////////////////////////
        vm.selectFork(ethForkId);

        (
            eigenAgent,
            execNonce
        ) = getEigenAgentAndExecNonce(deployer);

        require(address(eigenAgent) != address(0), "User must have an EigenAgent");
        expiry = block.timestamp + 1 hours;

        // same addresses as from 9b_processClaimRewards.s.sol
        EARNERS = [
            address(eigenAgent),
            address(0xAbAc0Ee51946B38a02AD8150fa85E9147bC8851F), // predicted eigen agent1
            address(0x1Ceb858C292Db256EF7E378dD85D8b23D7D96E63), // predicted eigen agent2
            address(4)
        ];

        REWARDS_AMOUNTS = [
            REWARDS_AMOUNT_1,
            REWARDS_AMOUNT_2,
            REWARDS_AMOUNT_3,
            REWARDS_AMOUNT_4
        ];

        earnerIndexes[EARNERS[0]] = 0;
        earnerIndexes[EARNERS[1]] = 1;
        earnerIndexes[EARNERS[2]] = 2;
        earnerIndexes[EARNERS[3]] = 3;

        IRewardsCoordinator.DistributionRoot memory distRoot = rewardsCoordinator.getCurrentDistributionRoot();
        uint32 currentDistRootIndex = uint32(rewardsCoordinator.getDistributionRootsLength()) - 1;

        // In production, get earnerIndex and proof for user from some database (from Eigenlayer)
        // where they were stored when submitting the rewards tree
        // For testing, we simply re-create the rewards tree, and generate the proofs from it
        TestRewardsTree memory tree = createEarnerTreeOneToken(
            rewardsCoordinator,
            EARNERS,
            address(tokenL1),
            REWARDS_AMOUNTS
        );

        uint32 earnerIndex = earnerIndexes[address(eigenAgent)];
        require(earnerIndex != 0, "User's EigenAgent not eligible for rewards claim");
        bytes memory proof = generateClaimProof(tree, earnerIndex);

        IRewardsCoordinator.RewardsMerkleClaim memory claim = createClaimOneToken(
            rewardsCoordinator,
            currentDistRootIndex,
            address(eigenAgent),
            earnerIndex,
            proof,
            address(tokenL1),
            REWARDS_AMOUNTS[earnerIndex]
        );

        // Simulate claiming via EigenAgent on L1
        // Note: do not put this between vm.startBroadcast()
        vm.prank(deployer);
        eigenAgent.execute(
            address(rewardsCoordinator), // to
            0, // value
            encodeProcessClaimMsg(claim, address(eigenAgent)),
            0 // operation: 0 for calls
        );

        // sign the message for EigenAgent to execute Eigenlayer command
        bytes memory messageWithSignature_PC = signMessageForEigenAgentExecution(
            deployerKey,
            address(eigenAgent),
            EthSepolia.ChainId, // destination chainid where EigenAgent lives
            address(rewardsCoordinator),
            encodeProcessClaimMsg(claim, address(eigenAgent)),
            execNonce,
            expiry
        );

        ///////////////////////////////////////////////
        // L2: Send a rewards processClaim message
        ///////////////////////////////////////////////
        vm.selectFork(l2ForkId);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](0);

        uint256 gasLimit = senderHooks.getGasLimitForFunctionSelector(
            IRewardsCoordinator.processClaim.selector
        );
        uint256 routerFees = getRouterFeesL2(
            address(receiverContract),
            string(messageWithSignature_PC),
            tokenAmounts,
            gasLimit
        );

        vm.startBroadcast(deployer);

        senderContract.sendMessagePayNative{value: routerFees}(
            EthSepolia.ChainSelector, // destination chain
            address(receiverContract),
            string(messageWithSignature_PC),
            tokenAmounts,
            0 // use default gasLimit for this function
        );

        vm.stopBroadcast();
    }
}
