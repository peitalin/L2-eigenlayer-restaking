// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";
import {console} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {IStrategy} from "@eigenlayer-contracts/interfaces/IStrategy.sol";

import {SenderHooks} from "../src/SenderHooks.sol";
import {BaseSepolia, EthSepolia} from "../script/Addresses.sol";



contract UnitTests_SenderHooks is BaseTestEnvironment {

    uint256 amount = 0.003 ether;
    address mockEigenAgent = vm.addr(3333);
    uint256 expiry = block.timestamp + 1 hours;
    uint32 startBlock = uint32(block.number);
    uint256 execNonce = 0;
    uint256 withdrawalNonce = 0;

    error AddressZero(string msg);
    error OnlySendFundsForDeposits(string msg);

    function setUp() public {
        setUpLocalEnvironment();
    }

    /*
     *
     *
     *             Tests
     *
     *
     */

    function test_SetAndGet_SenderCCIP() public {

        vm.expectRevert("Ownable: caller is not the owner");
        senderHooks.setSenderCCIP(address(senderContract));

        vm.expectRevert(abi.encodeWithSelector(AddressZero.selector, "SenderCCIP cannot be address(0)"));
        vm.prank(deployer);
        senderHooks.setSenderCCIP(address(0));

        vm.prank(deployer);
        senderHooks.setSenderCCIP(address(senderContract));

        vm.assertEq(senderHooks.getSenderCCIP(), address(senderContract));
    }

    function test_SetAndGet_GasLimits_SenderHooks() public {

        uint256[] memory gasLimits = new uint256[](2);
        gasLimits[0] = 1_000_000;
        gasLimits[1] = 800_000;

        bytes4[] memory functionSelectors = new bytes4[](2);
        functionSelectors[0] = 0xeee000aa;
        functionSelectors[1] = 0xccc555ee;

        bytes4[] memory functionSelectors2 = new bytes4[](3);
        functionSelectors2[0] = 0xeee000aa;
        functionSelectors2[1] = 0xccc555ee;
        functionSelectors2[2] = 0xaaa222ff;

        vm.startBroadcast(deployerKey);

        vm.expectRevert("input arrays must have the same length");
        senderHooks.setGasLimitsForFunctionSelectors(
            functionSelectors2,
            gasLimits
        );

        vm.expectEmit(true, true, false, false);
        emit SenderHooks.SetGasLimitForFunctionSelector(functionSelectors[0], gasLimits[0]);
        vm.expectEmit(true, true, false, false);
        emit SenderHooks.SetGasLimitForFunctionSelector(functionSelectors[1], gasLimits[1]);
        senderHooks.setGasLimitsForFunctionSelectors(
            functionSelectors,
            gasLimits
        );

        // Return default gasLimit of 400_000 for undefined function selectors
        vm.assertEq(senderHooks.getGasLimitForFunctionSelector(0xffeeaabb), 200_000);

        // gas limits should be set
        vm.assertEq(senderHooks.getGasLimitForFunctionSelector(functionSelectors[0]), 1_000_000);
        vm.assertEq(senderHooks.getGasLimitForFunctionSelector(functionSelectors[1]), 800_000);

        vm.stopBroadcast();
    }

    function test_DisableInitializers_SenderHooks() public {
        SenderHooks sHooks = new SenderHooks();
        // _disableInitializers on contract implementations
        vm.expectRevert("Initializable: contract is already initialized");
        sHooks.initialize();
    }

    function test_BeforeSend_Commits_WithdrawalTransferRoot() public {

        vm.startBroadcast(address(senderContract));

        (
            bytes32 withdrawalRoot,
            bytes memory messageWithSignature_CW
        ) = mockCompleteWithdrawalMessage(bobKey);

        console.log("tokenL1", address(tokenL1));

        // called by senderContract
        vm.expectRevert(abi.encodeWithSelector(
            OnlySendFundsForDeposits.selector, "Only send funds for deposit messages"));
        senderHooks.beforeSendCCIPMessage(
            abi.encode(string(messageWithSignature_CW)), // CCIP string encodes when messaging
            BaseSepolia.BridgeToken,
            amount
        );

        uint256 amountZero = 0 ether;

        bytes32 withdrawalAgentOwnerRoot = calculateWithdrawalTransferRoot(
            withdrawalRoot,
            amountZero,
            bob
        );

        vm.expectEmit(false, false, false, false);
        emit SenderHooks.WithdrawalTransferRootCommitted(
            withdrawalAgentOwnerRoot,
            mockEigenAgent, // withdrawer
            amountZero, // must be 0 ether for non-deposit calls
            bob // signer
        );
        // called by senderContract
        senderHooks.beforeSendCCIPMessage(
            abi.encode(string(messageWithSignature_CW)), // CCIP string encodes when messaging
            BaseSepolia.BridgeToken,
            amountZero
        );

        vm.stopBroadcast();
    }

    function test_BeforeSendCCIPMessage_OnlySenderCCIP(uint256 signerKey) public {

        vm.assume(signerKey < type(uint256).max / 2); // EIP-2: secp256k1 curve order / 2
        vm.assume(signerKey > 1);
        address alice = vm.addr(signerKey);

        vm.startBroadcast(alice);
        {
            (
                , // bytes32 withdrawalRoot,
                bytes memory messageWithSignature_CW
            ) = mockCompleteWithdrawalMessage(bobKey);

            // Should revert if called by anyone other than senderContract
            vm.expectRevert("not called by SenderCCIP");
            senderHooks.beforeSendCCIPMessage(
                abi.encode(string(messageWithSignature_CW)), // CCIP string encodes when messaging
                BaseSepolia.BridgeToken,
                0 ether
            );
        }
        vm.stopBroadcast();
    }

    function test_BeforeSendCCIPMessage_WithdrawalTransferRoot_TokenCannotBeNull() public {

        vm.startBroadcast(address(senderContract));

        (
            bytes32 withdrawalRoot,
            bytes memory messageWithSignature_CW
        ) = mockCompleteWithdrawalMessage(bobKey);

        require(withdrawalRoot != bytes32(abi.encode(0)), "withdrawalRoot cannot be 0x0");

        vm.expectRevert("SenderHooks._commitWithdrawalTransferRootInfo: cannot commit tokenL2 as address(0)");
        senderHooks.beforeSendCCIPMessage(
            abi.encode(string(messageWithSignature_CW)), // CCIP string encodes when messaging
            address(0), // tokenL2
            0 ether
        );

        vm.stopBroadcast();
    }

    function test_BeforeSendCCIPMessage_RewardsTransferRoot_TokenCannotBeNull() public {

        vm.startBroadcast(address(senderContract));

        (
            bytes32 rewardsRoot,
            bytes memory messageWithSignature_PC
        ) = mockRewardsClaimMessage(bobKey);

        require(rewardsRoot != bytes32(abi.encode(0)), "rewardsRoot cannot be 0x0");

        vm.expectRevert("SenderHooks._commitRewardsTransferRootInfo: cannot commit tokenL2 as address(0)");
        senderHooks.beforeSendCCIPMessage(
            abi.encode(string(messageWithSignature_PC)), // CCIP string encodes when messaging
            address(0), // tokenL2
            0 ether
        );

        vm.stopBroadcast();
    }

    function mockRewardsClaimMessage(uint256 signerKey) public view returns (
        bytes32 rewardsRoot,
        bytes memory messageWithSignature_PC
    ) {

		IRewardsCoordinator.TokenTreeMerkleLeaf[] memory tokenLeaves;
        tokenLeaves = new IRewardsCoordinator.TokenTreeMerkleLeaf[](1);
		tokenLeaves[0] = IRewardsCoordinator.TokenTreeMerkleLeaf({
            token: tokenL1,
            cumulativeEarnings: 1 ether
        });

        address signer = vm.addr(signerKey);

		IRewardsCoordinator.EarnerTreeMerkleLeaf memory earnerLeaf;
        earnerLeaf = IRewardsCoordinator.EarnerTreeMerkleLeaf({
			earner: signer,
			earnerTokenRoot: rewardsCoordinator.calculateTokenLeafHash(tokenLeaves[0])
		});

        uint32[] memory tokenIndices = new uint32[](1);
        bytes[] memory tokenTreeProofs = new bytes[](1);
        tokenIndices[0] = 0;
        tokenTreeProofs[0] = abi.encode(bytes32(0x0));

		IRewardsCoordinator.RewardsMerkleClaim memory claim = IRewardsCoordinator.RewardsMerkleClaim({
			rootIndex: 0,
			earnerIndex: 0,
			earnerTreeProof: hex"",
			earnerLeaf: earnerLeaf,
			tokenIndices: tokenIndices,
			tokenTreeProofs: tokenTreeProofs,
			tokenLeaves: tokenLeaves
		});

        // sign the message for EigenAgent to execute Eigenlayer command
        messageWithSignature_PC = signMessageForEigenAgentExecution(
            signerKey,
            EthSepolia.ChainId, // destination chainid where EigenAgent lives
            address(rewardsCoordinator),
            encodeProcessClaimMsg(claim, signer),
            execNonce,
            expiry
        );

        rewardsRoot = calculateRewardsRoot(claim);
    }

    function mockCompleteWithdrawalMessage(uint256 signerKey) public view
        returns (
            bytes32 withdrawalRoot,
            bytes memory messageWithSignature_CW
        )
    {

        IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
        uint256[] memory sharesToWithdraw = new uint256[](1);
        strategiesToWithdraw[0] = strategy;
        sharesToWithdraw[0] = amount;

        IDelegationManager.Withdrawal memory withdrawal = IDelegationManager.Withdrawal({
            staker: mockEigenAgent,
            delegatedTo: vm.addr(5656),
            withdrawer: mockEigenAgent,
            nonce: withdrawalNonce,
            startBlock: startBlock,
            strategies: strategiesToWithdraw,
            shares: sharesToWithdraw
        });

        withdrawalRoot = calculateWithdrawalRoot(withdrawal);

        bytes memory completeWithdrawalMessage;
        {
            // create the completeWithdrawal message for Eigenlayer
            IERC20[] memory tokensToWithdraw = new IERC20[](1);
            tokensToWithdraw[0] = tokenL1;

            completeWithdrawalMessage = encodeCompleteWithdrawalMsg(
                withdrawal,
                tokensToWithdraw,
                0, //middlewareTimesIndex,
                true // receiveAsTokens
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_CW = signMessageForEigenAgentExecution(
                signerKey,
                EthSepolia.ChainId, // destination chainid where EigenAgent lives
                address(delegationManager),
                completeWithdrawalMessage,
                execNonce,
                expiry
            );
        }

        return (
            withdrawalRoot,
            messageWithSignature_CW
        );
    }

}
