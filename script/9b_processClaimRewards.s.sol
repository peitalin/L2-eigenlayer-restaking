// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";

import {BaseScript} from "./BaseScript.sol";
import {EthSepolia} from "./Addresses.sol";


contract ProcessClaimRewardsScript is BaseScript {

    uint256 deployerKey;
    address deployer;

    address TARGET_CONTRACT; // Contract that EigenAgent forwards calls to
    uint256 execNonce; // EigenAgent execution nonce
    uint256 expiry;
    IEigenAgent6551 eigenAgent;

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

        IRewardsCoordinator.DistributionRoot memory distRoot = rewardsCoordinator.getCurrentDistributionRoot();
        uint32 currentDistRootIndex = uint32(rewardsCoordinator.getDistributionRootsLength()) - 1;

        IRewardsCoordinator.RewardsMerkleClaim memory claim = createClaim(
            currentDistRootIndex,
            address(eigenAgent),
            0.1 ether, // amount to claim
            hex"", // proof is empty as theres only 1 claim (root)
            0 // earnerIndex
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

        uint256 gasLimit = senderHooks.getGasLimitForFunctionSelector(
            IRewardsCoordinator.processClaim.selector
        );
        uint256 routerFees = getRouterFeesL2(
            address(receiverContract),
            string(messageWithSignature_PC),
            address(tokenL2),
            0 ether,
            gasLimit
        );

        vm.startBroadcast(deployer);

        senderContract.sendMessagePayNative{value: routerFees}(
            EthSepolia.ChainSelector, // destination chain
            address(receiverContract),
            string(messageWithSignature_PC),
            address(tokenL2), // destination token
            0, // not sending tokens, just message
            0 // use default gasLimit for this function
        );

        vm.stopBroadcast();
    }

    /*
     *
     *
     *             Rewards Claims
     *
     *
     */

	function createClaim(
        uint32 rootIndex,
        address earner,
        uint256 amount,
        bytes memory proof,
        uint32 earnerIndex
    ) public view returns (IRewardsCoordinator.RewardsMerkleClaim memory claim) {

		IRewardsCoordinator.TokenTreeMerkleLeaf[] memory tokenLeaves;
        tokenLeaves = new IRewardsCoordinator.TokenTreeMerkleLeaf[](1);
		tokenLeaves[0] = IRewardsCoordinator.TokenTreeMerkleLeaf({
            token: tokenL1,
            cumulativeEarnings: amount
        });

		IRewardsCoordinator.EarnerTreeMerkleLeaf memory earnerLeaf;
        earnerLeaf = IRewardsCoordinator.EarnerTreeMerkleLeaf({
			earner: earner,
			earnerTokenRoot: rewardsCoordinator.calculateTokenLeafHash(tokenLeaves[0])
		});

        uint32[] memory tokenIndices = new uint32[](1);
        tokenIndices[0] = 0;
		// Only 1 claims entries in the TokenClaim tree, so proof is empty (just the root)
        bytes[] memory tokenTreeProofs = new bytes[](1);
        tokenTreeProofs[0] = hex"";

		return IRewardsCoordinator.RewardsMerkleClaim({
			rootIndex: rootIndex,
			earnerIndex: earnerIndex,
			earnerTreeProof: proof,
			earnerLeaf: earnerLeaf,
			tokenIndices: tokenIndices,
			tokenTreeProofs: tokenTreeProofs,
			tokenLeaves: tokenLeaves
		});
	}

}
