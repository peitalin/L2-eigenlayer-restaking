// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {TransparentUpgradeableProxy} from "@openzeppelin-v5-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-v5-contracts/proxy/transparent/ProxyAdmin.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IBurnMintERC20} from "@chainlink/shared/token/ERC20/IBurnMintERC20.sol";
import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {IRewardsCoordinatorTypes} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {Merkle} from "@eigenlayer-contracts/libraries/Merkle.sol";

import {ERC20Minter} from "../test/mocks/ERC20Minter.sol";
import {RewardsUtils} from "./RewardsUtils.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {BaseScript} from "./BaseScript.sol";

// Rewards Claiming Steps:
// 1) Post reward roots for staker's Eigenagent for the previous week.
// 2) Wait 1 hour for rewardRoot to finalise
// 3) Run processClaims script

// Note: you can only post rewardRoots once for each week. Once posted
// the RewardsCoordinator will reject rewardRoots posted for that timestamp, and you will have to
// wait a week to post another one for the next week (or re-deploy RewardsCoordinator).


contract SubmitRewardsScript is BaseScript {
    using SafeERC20 for IERC20;

    uint256 deployerKey;
    address deployer;

    address TARGET_CONTRACT; // Contract that EigenAgent forwards calls to
    IEigenAgent6551 eigenAgent;
    uint256 execNonce; // EigenAgent execution nonce

    uint32 secondsInWeek;
    uint32 timeNow;
    uint32 startOfTheWeek;
    uint32 startOfLastWeek;

    address[4] EARNERS;
    uint256[4] REWARDS_AMOUNTS1; // token1
    uint256 totalRewards1;

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
        ////// L1: Submit Reward Roots
        /////////////////////////////////////////////////////////////////
        vm.selectFork(ethForkId);

        (
            eigenAgent,
            execNonce
        ) = getEigenAgentAndExecNonce(deployer);

        EARNERS = [
            address(eigenAgent),
            address(0xAbAc0Ee51946B38a02AD8150fa85E9147bC8851F), // predicted eigen agent1
            address(0x1Ceb858C292Db256EF7E378dD85D8b23D7D96E63), // predicted eigen agent2
            address(4)
        ];
        REWARDS_AMOUNTS1 = [
            0.1 ether,
            0.2 ether,
            0.3 ether,
            0.4 ether
        ];
        totalRewards1 = 1 ether;

        secondsInWeek = 604800;
        timeNow = uint32(block.timestamp);
        startOfTheWeek = uint32(block.timestamp) - (uint32(block.timestamp) % secondsInWeek);
        startOfLastWeek = startOfTheWeek - secondsInWeek;

        RewardsUtils.TestRewardsTree memory tree = submitRewards();

        bytes memory proof0 = RewardsUtils.generateClaimProof(tree, 0);
        bytes memory proof1 = RewardsUtils.generateClaimProof(tree, 1);
        bytes memory proof2 = RewardsUtils.generateClaimProof(tree, 2);
        bytes memory proof3 = RewardsUtils.generateClaimProof(tree, 3);
        // Save the proofs and earnerIndexes for each user and use them in the frontend
        // to load and submit processClaims requests from L2
    }

    /*
     *
     *
     *             Setup Eigenlayer Rewards Claims
     *
     *
     */

    function submitRewards() internal returns (RewardsUtils.TestRewardsTree memory) {

        uint256 numRootsBefore = rewardsCoordinator.getDistributionRootsLength();

        RewardsUtils.TestRewardsTree memory tree = RewardsUtils.createEarnerTreeOneToken(
            rewardsCoordinator,
            EARNERS,
            address(tokenL1),
            REWARDS_AMOUNTS1
        );

        // validate earners claims, and see if their proofs are ok.
        bytes memory proof0 = RewardsUtils.generateClaimProof(tree, 0);
        bytes memory proof1 = RewardsUtils.generateClaimProof(tree, 1);
        bytes memory proof2 = RewardsUtils.generateClaimProof(tree, 2);
        bytes memory proof3 = RewardsUtils.generateClaimProof(tree, 3);

        bytes32 generatedRoot0 = Merkle.processInclusionProofKeccak(proof0, tree.root, 0);
        bytes32 generatedRoot1 = Merkle.processInclusionProofKeccak(proof1, tree.root, 1);
        bytes32 generatedRoot2 = Merkle.processInclusionProofKeccak(proof2, tree.root, 2);
        bytes32 generatedRoot3 = Merkle.processInclusionProofKeccak(proof3, tree.root, 3);

        require(tree.root == generatedRoot0, "tree.root must equal generatedRoot0");
        require(tree.root == generatedRoot1, "tree.root must equal generatedRoot1");
        require(tree.root == generatedRoot2, "tree.root must equal generatedRoot2");
        require(tree.root == generatedRoot3, "tree.root must equal generatedRoot3");

        uint32 startTimestamp = startOfLastWeek; // startTimestamp, must be a multiple of 604800 (7 days)
        uint32 duration = 604800; // duration, must be a multiple of 604800
        uint32 rewardsCalculationEndTimestamp = startOfLastWeek + duration;

        vm.startBroadcast(deployer);
        {
            // mint tokens to deployer
            IBurnMintERC20(address(tokenL1)).mint(deployer, totalRewards1);
            // submit rewardsRoot
            rewardsCoordinator.submitRoot(tree.root, rewardsCalculationEndTimestamp);
            // transfer rewards amount to RewardsCoordinator
            IERC20(address(tokenL1)).safeTransfer(address(rewardsCoordinator), totalRewards1);
        }
        vm.stopBroadcast();

        require(
            rewardsCoordinator.getDistributionRootsLength() == numRootsBefore + 1,
            "There should be 1 more DistributionRoot"
        );

        return tree;
    }

}
