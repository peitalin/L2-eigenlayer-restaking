// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IBurnMintERC20} from "@chainlink/shared/token/ERC20/IBurnMintERC20.sol";
import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {IRewardsCoordinatorTypes} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {Merkle} from "@eigenlayer-contracts/libraries/Merkle.sol";

import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {BaseScript} from "./BaseScript.sol";

// Rewards Claiming Steps:
// 1) Post reward roots for staker's Eigenagent for the previous week.
// 2) Wait 1 hour for rewardRoot to finalise
// 3) Run processClaims script

// Note: you can only post rewardRoots once for each week. Once posted
// the RewardsCoordinator will reject rewardRoots posted for that timestamp, and you will have to
// wait a week to post another one for the next week (or re-deploy RewardsCoordinator).
uint256 constant REWARDS_AMOUNT = 0.1 ether;

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

        secondsInWeek = 604800;
        timeNow = uint32(block.timestamp);
        startOfTheWeek = uint32(block.timestamp) - (uint32(block.timestamp) % secondsInWeek);
        startOfLastWeek = startOfTheWeek - secondsInWeek;

        (
            bytes memory proof,
            uint256 earnerIndex
        ) = submitRewards(address(eigenAgent), REWARDS_AMOUNT);
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

    function submitRewards(address _earner, uint256 amount) internal returns (bytes memory, uint32) {

        uint256 numRootsBefore = rewardsCoordinator.getDistributionRootsLength();

        // See CCIP_ForkTest5_RewardsProcessClaim.t.sol for multi-user + multi-token example.
        bytes32 root = rewardsCoordinator.calculateEarnerLeafHash(
            IRewardsCoordinatorTypes.EarnerTreeMerkleLeaf({
                earner: _earner,
                earnerTokenRoot: rewardsCoordinator.calculateTokenLeafHash(
                    IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
                        token: tokenL1,
                        cumulativeEarnings: REWARDS_AMOUNT
                    })
                )
            })
        );

		// Only 1 claims entries in the TokenClaim tree, so proof is empty (just the root)
        bytes memory proof = hex"";
        uint32 earnerIndex = 0; // 0-th element in the bottom of the tree, left-to-right
        bytes32 generatedRoot = Merkle.processInclusionProofKeccak(proof, root, earnerIndex);

        require(root == generatedRoot, "root must equal generatedRoot");

        uint32 startTimestamp = startOfLastWeek; // startTimestamp, must be a multiple of 604800 (7 days)
        uint32 duration = 604800; // duration, must be a multiple of 604800
        uint32 rewardsCalculationEndTimestamp = startOfLastWeek + duration;

        vm.startBroadcast(deployer);
        // mint tokens to deployer
        IBurnMintERC20(address(tokenL1)).mint(deployer, REWARDS_AMOUNT);
        // approve rewardsCoordinator to spend tokens
        tokenL1.approve(address(rewardsCoordinator), REWARDS_AMOUNT);
        // submit rewardsRoot
        rewardsCoordinator.submitRoot(root, rewardsCalculationEndTimestamp);
        // transfer rewards amount to RewardsCoordinator
        tokenL1.safeTransfer(address(rewardsCoordinator), REWARDS_AMOUNT);
        vm.stopBroadcast();

        require(
            rewardsCoordinator.getDistributionRootsLength() == numRootsBefore + 1,
            "There should be 1 more DistributionRoot"
        );

        return (proof, earnerIndex);
    }

}
