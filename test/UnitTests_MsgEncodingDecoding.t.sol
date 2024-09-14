// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";

import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {
    EigenlayerMsgDecoders,
    DelegationDecoders,
    AgentOwnerSignature,
    TransferToAgentOwnerMsg
} from "../src/utils/EigenlayerMsgDecoders.sol";
import {EigenlayerMsgEncoders} from "../src/utils/EigenlayerMsgEncoders.sol";
import {FunctionSelectorDecoder} from "../src/utils/FunctionSelectorDecoder.sol";
import {EthSepolia} from "../script/Addresses.sol";


contract UnitTests_MsgEncodingDecoding is BaseTestEnvironment {

    EigenlayerMsgDecoders public eigenlayerMsgDecoders;

    uint256 amount;
    address staker;
    uint256 expiry;
    uint256 execNonce;

    function setUp() public {

        setUpLocalEnvironment();

        eigenlayerMsgDecoders = new EigenlayerMsgDecoders();

        amount = 0.0077 ether;
        staker = deployer;
        expiry = 86421;
        execNonce = 0;
    }

    /*
     *
     *
     *             Tests
     *
     *
     */

    function test_DecodeFunctionSelectors() public view {

        bytes memory message1 = hex"00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000044f7e784ef00000000000000000000000000000000000000000000000000000000000000020000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c00000000000000000000000000000000000000000000000000000000";
        bytes4 functionSelector1 = FunctionSelectorDecoder.decodeFunctionSelector(message1);
        require(functionSelector1 == 0xf7e784ef, "wrong functionSelector");

        bytes memory message2 = abi.encode(string(abi.encodeWithSelector(
            bytes4(keccak256("depositIntoStrategyWithSignature(address,address,uint256,address,uint256,bytes)")),
            expiry,
            address(strategy),
            address(tokenL1),
            amount,
            staker,
            hex"3de99eb6c4e298a2332589fdcfd751c8e1adf9865da06eff5771b6c59a41c8ee3b8ef0a097ef6f09deee5f94a141db1a8d59bdb1fd96bc1b31020830a18f76d51c"
        )));
        bytes4 functionSelector2 = FunctionSelectorDecoder.decodeFunctionSelector(message2);
        require(functionSelector2 == 0x32e89ace, "wrong functionSelector");
    }

    function test_Decode_AgentOwnerSignature() public view {

        bytes memory messageToEigenlayer = encodeDepositIntoStrategyMsg(
            address(strategy),
            address(tokenL1),
            amount
        );

        bytes memory messageWithSignature = signMessageForEigenAgentExecution(
            deployerKey,
            block.chainid,
            address(strategy),
            messageToEigenlayer,
            execNonce,
            expiry
        );

        (
            // message
            address _strategy,
            address _token,
            uint256 _amount,
            // message signature
            address _signer,
            uint256 _expiry,
            bytes memory _signature
        ) = eigenlayerMsgDecoders.decodeDepositIntoStrategyMsg(
            // CCIP string and encodes message when sending
            abi.encode(string(messageWithSignature))
        );

        (
            address _signer2,
            uint256 _expiry2,
            bytes memory _signature2
        ) = AgentOwnerSignature.decodeAgentOwnerSignature(
            abi.encode(string(messageWithSignature)),
            196
        ); // for depositIntoStrategy

        // compare vs original inputs
        require(_signer == vm.addr(deployerKey), "decodeAgentOwnerSignature: signer not original address");
        require(_expiry == expiry, "decodeAgentOwnerSignature: expiry not original expiry");
        require(_amount == amount, "decodeAgentOwnerSignature: amount not original amount");
        require(_token == address(tokenL1), "decodeAgentOwnerSignature: token not original tokenL1");
        require(_strategy == address(strategy), "decodeAgentOwnerSignature: strategy not original strategy");

        // compare decodeAgentOwner vs decodeDepositIntoStrategy
        require(_signer == _signer2, "decodeAgentOwnerSignature: signer did not match");
        require(_expiry == _expiry2, "decodeAgentOwnerSignature: expiry did not match");
        require(
            keccak256(_signature) == keccak256(_signature2),
            "decodeAgentOwnerSignature: signature incorrect"
        );
    }

    function test_Decode_MintEigenAgent() public view {

        // use EigenlayerMsgEncoders for coverage.
        bytes memory messageToMint = EigenlayerMsgEncoders.encodeMintEigenAgentMsg(staker);
        // CCIP turns the message into string when sending
        bytes memory messageCCIP = abi.encode(string(messageToMint));

        address recipient = eigenlayerMsgDecoders.decodeMintEigenAgent(messageCCIP);

        require(recipient == staker, "mintEigenAgent: staker does not match");
    }

    /*
     *
     *
     *                   Deposits
     *
     *
    */

    function test_Decode_DepositIntoStrategy6551Msg() public view {

        bytes memory messageToEigenlayer = encodeDepositIntoStrategyMsg(
            address(strategy),
            address(tokenL1),
            amount
        );

        bytes memory messageWithSignature = signMessageForEigenAgentExecution(
            deployerKey,
            block.chainid,
            address(strategy),
            messageToEigenlayer,
            execNonce,
            expiry
        );

        // CCIP turns the message into string when sending
        bytes memory messageWithSignatureCCIP = abi.encode(string(messageWithSignature));

        (
            // message
            address _strategy,
            address _token,
            uint256 _amount,
            // message signature
            address _signer,
            uint256 _expiry,
            bytes memory _signature
        ) = eigenlayerMsgDecoders.decodeDepositIntoStrategyMsg(messageWithSignatureCCIP);

        require(address(_strategy) == address(strategy), "strategy does not match");
        require(address(tokenL1) == _token, "token error: decodeDepositIntoStrategyMsg");
        require(amount == _amount, "amount error: decodeDepositIntoStrategyMsg");

        require(_signature.length == 65, "invalid signature length");
        require(_signer == staker, "staker does not match");
        require(expiry == _expiry, "expiry error: decodeDepositIntoStrategyMsg");
    }

    /*
     *
     *
     *                   Queue Withdrawals
     *
     *
    */

    function test_Decode_Array_QueueWithdrawals() public view {

        IStrategy[] memory strategiesToWithdraw0 = new IStrategy[](1);
        IStrategy[] memory strategiesToWithdraw1 = new IStrategy[](1);
        IStrategy[] memory strategiesToWithdraw2 = new IStrategy[](1);

        uint256[] memory sharesToWithdraw0 = new uint256[](1);
        uint256[] memory sharesToWithdraw1 = new uint256[](1);
        uint256[] memory sharesToWithdraw2 = new uint256[](1);

        strategiesToWithdraw0[0] = IStrategy(0xb111111AD20E9d85d5152aE68f45f40A11111111);
        strategiesToWithdraw1[0] = IStrategy(0xb222222AD20e9D85d5152ae68F45f40a22222222);
        strategiesToWithdraw2[0] = IStrategy(0xb333333AD20e9D85D5152aE68f45F40A33333333);

        sharesToWithdraw0[0] = 0.010101 ether;
        sharesToWithdraw1[0] = 0.020202 ether;
        sharesToWithdraw2[0] = 0.030303 ether;

        IDelegationManager.QueuedWithdrawalParams[] memory QWPArray =
            new IDelegationManager.QueuedWithdrawalParams[](3);

        {
            IDelegationManager.QueuedWithdrawalParams memory queuedWithdrawal0;
            IDelegationManager.QueuedWithdrawalParams memory queuedWithdrawal1;
            IDelegationManager.QueuedWithdrawalParams memory queuedWithdrawal2;

            queuedWithdrawal0 = IDelegationManager.QueuedWithdrawalParams({
                strategies: strategiesToWithdraw0,
                shares: sharesToWithdraw0,
                withdrawer: deployer
            });
            queuedWithdrawal1 = IDelegationManager.QueuedWithdrawalParams({
                strategies: strategiesToWithdraw1,
                shares: sharesToWithdraw1,
                withdrawer: vm.addr(0x1)
            });
            queuedWithdrawal2 = IDelegationManager.QueuedWithdrawalParams({
                strategies: strategiesToWithdraw2,
                shares: sharesToWithdraw2,
                withdrawer: vm.addr(0x2)
            });

            QWPArray[0] = queuedWithdrawal0;
            QWPArray[1] = queuedWithdrawal1;
            QWPArray[2] = queuedWithdrawal2;
        }

        bytes memory message_QW;
        bytes memory messageWithSignature_QW;
        {
            message_QW = encodeQueueWithdrawalsMsg(
                QWPArray
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_QW = signMessageForEigenAgentExecution(
                deployerKey,
                block.chainid, // destination chainid where EigenAgent lives
                address(123123), // StrategyManager to approve + deposit
                message_QW,
                execNonce,
                expiry
            );
        }

        (
            IDelegationManager.QueuedWithdrawalParams[] memory decodedQW,
            address signer,
            uint256 expiry2,
            bytes memory _signature
        ) = eigenlayerMsgDecoders.decodeQueueWithdrawalsMsg(
            // CCIP string-encodes the message when sending
            abi.encode(string(
                messageWithSignature_QW
            ))
        );

        // signature
        require(_signature.length == 65, "signature bad length: decodeQueueWithdrawalsMsg");
        require(signer == deployer, "incorrect signer: decodeQueueWithdrawalsMsg");
        require(expiry == expiry2, "incorrect decoding: decodeQueueWithdrawalsMsg");
        // strategies
        require(
            decodedQW[2].strategies[0] == strategiesToWithdraw2[0],
            "incorrect decoding: decodeQueueWithdrawalsMsg[2]: strategies"
        );
        // shares
        require(
            decodedQW[0].shares[0] == sharesToWithdraw0[0],
            "incorrect decoding: decodeQueueWithdrawalsMsg[0]: shares"
        );
        require(
            decodedQW[1].shares[0] == sharesToWithdraw1[0],
            "incorrect decoding: decodeQueueWithdrawalsMsg[1]: shares"
        );
        // withdrawers
        require(
            decodedQW[0].withdrawer == QWPArray[0].withdrawer,
            "incorrect decoding: decodeQueueWithdrawalsMsg[0]: withdrawer"
        );
        require(
            decodedQW[1].withdrawer == QWPArray[1].withdrawer,
            "incorrect decoding: decodeQueueWithdrawalsMsg[1]: withdrawer"
        );
        require(
            decodedQW[2].withdrawer == QWPArray[2].withdrawer,
            "incorrect decoding: decodeQueueWithdrawalsMsg[2]: withdrawer"
        );
    }

    function test_Decode_Revert_ZeroLenArray_QueueWithdrawals() public {

        IDelegationManager.QueuedWithdrawalParams[] memory QWPArray =
            new IDelegationManager.QueuedWithdrawalParams[](0);

        bytes memory message_QW;
        bytes memory messageWithSignature_QW;
        {
            message_QW = encodeQueueWithdrawalsMsg(
                QWPArray
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_QW = signMessageForEigenAgentExecution(
                deployerKey,
                block.chainid, // destination chainid where EigenAgent lives
                address(123123), // StrategyManager to approve + deposit
                message_QW,
                execNonce,
                expiry
            );
        }

        vm.expectRevert("decodeQueueWithdrawalsMsg: arrayLength must be at least 1");
        eigenlayerMsgDecoders.decodeQueueWithdrawalsMsg(
            // CCIP string-encodes the message when sending
            abi.encode(string(
                messageWithSignature_QW
            ))
        );
    }

    /*
     *
     *
     *                   Complete Withdrawals
     *
     *
    */

    function test_Decode_CompleteQueuedWithdrawal() public view {

        IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
        uint256[] memory sharesToWithdraw = new uint256[](1);

        strategiesToWithdraw[0] = strategy;
        sharesToWithdraw[0] = 0.00321 ether;

        IDelegationManager.Withdrawal memory withdrawal = IDelegationManager.Withdrawal({
            staker: deployer,
            delegatedTo: address(0x0),
            withdrawer: deployer,
            nonce: 0,
            startBlock: uint32(block.number),
            strategies: strategiesToWithdraw,
            shares: sharesToWithdraw
        });

        IERC20[] memory tokensToWithdraw = new IERC20[](1);
        tokensToWithdraw[0] = tokenL1;
        uint256 middlewareTimesIndex = 0; // not used, used when slashing is enabled;
        bool receiveAsTokens = true;

        bytes memory message_CW;
        bytes memory messageWithSignature_CW;
        {
            message_CW = encodeCompleteWithdrawalMsg(
                withdrawal,
                tokensToWithdraw,
                middlewareTimesIndex,
                receiveAsTokens
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_CW = signMessageForEigenAgentExecution(
                deployerKey,
                block.chainid, // destination chainid where EigenAgent lives
                address(123123), // StrategyManager to approve + deposit
                message_CW,
                execNonce,
                expiry
            );
        }

        (
            IDelegationManager.Withdrawal memory _withdrawal,
            IERC20[] memory _tokensToWithdraw,
            , // uint256 _middlewareTimesIndex
            bool _receiveAsTokens,
            address _signer,
            uint256 _expiry,
            bytes memory _signature
        ) = eigenlayerMsgDecoders.decodeCompleteWithdrawalMsg(
            // CCIP string-encodes the message when sending
            abi.encode(string(
                messageWithSignature_CW
            ))
        );

        require(_signature.length == 65, "signature incorrect length: decodeCompleteWithdrawalsMsg");
        require(_signer == deployer, "incorrect signer: decodeCompleteWithdrawalsMsg");
        require(_expiry == expiry, "incorrect expiry: decodeCompleteWithdrawalsMsg");

        require(_withdrawal.shares[0] == withdrawal.shares[0], "decodeCompleteWithdrawalMsg shares error");
        require(_withdrawal.staker == withdrawal.staker, "decodeCompleteWithdrawalMsg staker error");
        require(_withdrawal.withdrawer == withdrawal.withdrawer, "decodeCompleteWithdrawalMsg withdrawer error");
        require(address(_tokensToWithdraw[0]) == address(tokensToWithdraw[0]), "decodeCompleteWithdrawalMsg tokensToWithdraw error");
        require(_receiveAsTokens == receiveAsTokens, "decodeCompleteWithdrawalMsg error");
    }

    function test_FunctionSelectors_CompleteQueueWithdrawal() public pure {
        bytes4 fselector1 = IDelegationManager.completeQueuedWithdrawal.selector;
        bytes4 fselector2 = bytes4(keccak256("completeQueuedWithdrawal((address,address,address,uint256,uint32,address[],uint256[]),address[],uint256,bool)"));
        // bytes4 fselector3 = 0x60d7faed;
        require(fselector1 == fselector2, "function selectors incorrect: completeQueuedWithdrawal");
    }

    function test_Decode_TransferToAgentOwnerMsg() public view {

        bytes32 withdrawalRoot = 0x8c20d3a37feccd4dcb9fa5fbd299b37db00fde77cbb7540e2850999fc7d8ec77;

        address bob = vm.addr(8881);
        bytes32 withdrawalTransferRoot = keccak256(abi.encode(withdrawalRoot, amount, bob));

        TransferToAgentOwnerMsg memory tta_msg = eigenlayerMsgDecoders.decodeTransferToAgentOwnerMsg(
            abi.encode(string(
                encodeHandleTransferToAgentOwnerMsg(
                    calculateWithdrawalTransferRoot(
                        withdrawalRoot,
                        amount,
                        bob
                    )
                )
            ))
        );

        require(tta_msg.withdrawalTransferRoot == withdrawalTransferRoot, "incorrect withdrawalTransferRoot");
    }

    /*
     *
     *
     *                   Delegation
     *
     *
    */

    function test_Decode_DelegateTo() public {

        address eigenAgent = vm.addr(0x1);
        address operator = vm.addr(0x2);
        bytes32 approverSalt = 0x0000000000000000000000000000000000000000000000000000000000004444;
        execNonce = 0;
        uint256 sig1_expiry = block.timestamp + 50 minutes;

        ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry;
        {

            bytes32 digestHash1 = calculateDelegationApprovalDigestHash(
                eigenAgent,
                operator,
                operator,
                approverSalt,
                sig1_expiry,
                address(delegationManager),
                EthSepolia.ChainSelector
            );

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerKey, digestHash1);
            bytes memory signature1 = abi.encodePacked(r, s, v);

            approverSignatureAndExpiry = ISignatureUtils.SignatureWithExpiry({
                signature: signature1,
                expiry: sig1_expiry
            });
        }

        ///////////////////////////////////////
        /// Append EiggenAgent Signature
        ///////////////////////////////////////

        bytes memory message_DT;
        bytes memory messageWithSignature_DT;
        {
            message_DT = encodeDelegateTo(
                operator,
                approverSignatureAndExpiry,
                approverSalt
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_DT = signMessageForEigenAgentExecution(
                deployerKey,
                block.chainid, // destination chainid where EigenAgent lives
                address(123123), // StrategyManager to approve + deposit
                message_DT,
                execNonce,
                sig1_expiry
            );
        }

        // CCIP turns the message into string when sending
        bytes memory message = abi.encode(string(messageWithSignature_DT));

        (
            address _operator,
            ISignatureUtils.SignatureWithExpiry memory _approverSignatureAndExpiry,
            bytes32 _approverSalt,
            address _signer,
            , // uint256 _expiryEigenAgent
            // bytes memory _signatureEigenAgent
        ) = DelegationDecoders.decodeDelegateToMsg(message);

        require(operator == _operator, "operator incorrect");
        require(deployer == _signer, "signer incorrect");
        require(approverSalt == _approverSalt, "approverSalt incorrect");

        require(
            approverSignatureAndExpiry.expiry == _approverSignatureAndExpiry.expiry,
            "approver signature expiry incorrect"
        );
        require(
            keccak256(approverSignatureAndExpiry.signature) == keccak256(_approverSignatureAndExpiry.signature),
            "approver signature incorrect"
        );
    }

    function test_Decode_Undelegate() public {

        address staker1 = vm.addr(0x1);
        execNonce = 0;
        expiry = block.timestamp + 1 hours;

        bytes memory message_UD;
        bytes memory messageWithSignature_UD;
        {
            message_UD = encodeUndelegateMsg(
                staker1
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_UD = signMessageForEigenAgentExecution(
                deployerKey,
                block.chainid, // destination chainid where EigenAgent lives
                address(123123), // StrategyManager to approve + deposit
                message_UD,
                execNonce,
                expiry
            );
        }

        (
            address _staker1,
            address signer,
            uint256 expiryEigenAgent,
            // bytes memory signatureEigenAgent
        ) = DelegationDecoders.decodeUndelegateMsg(
            abi.encode(string(
                messageWithSignature_UD
            ))
        );

        require(staker1 == _staker1, "staker incorrect");
        require(signer == deployer, "signer incorrect");
        require(expiry == expiryEigenAgent, "signature expiry incorrect");
    }

    /*
     *
     *
     *                   Rewards Claims
     *
     *
    */

    function test_Decode_RewardsCoordinator_ProcessClaim() public view {

        // struct RewardsMerkleClaim {
        //     uint32 rootIndex;
        //     uint32 earnerIndex;
        //     bytes earnerTreeProof;
        //     EarnerTreeMerkleLeaf earnerLeaf;
        //     uint32[] tokenIndices;
        //     bytes[] tokenTreeProofs;
        //     TokenTreeMerkleLeaf[] tokenLeaves;
        // }
        // struct EarnerTreeMerkleLeaf {
        //     address earner;
        //     bytes32 earnerTokenRoot;
        // }
        // struct TokenTreeMerkleLeaf {
        //     IERC20 token;
        //     uint256 cumulativeEarnings;
        // }

        // https://dashboard.tenderly.co/tx/holesky/0x0c6039e0fa7d6a0e32f4f62114a87fb1d5e4e37ff84dbdf9cc2d6c672d5af9de/debugger?trace=0.2

        bytes memory earnerTreeProof = hex"32c3756cc20bcbdb7f8b25dcb3b904ea271776626d79cf1797932298c3bc5c628a09335bd33183649a1338e1ce19dcc11b6e7500659b71ddeb3680855b6eeffdd879bbbe67f12fc80b7df9df2966012d54b23b2c1265c708cc64b12d38acf88a82277145d984d6a9dc5bdfa13cee09e543b810cef077330bd5828b746b8c92bb622731e95bf8721578fa6c5e1ceaf2e023edb2b9c989c7106af8455ceae4aaad1891758b2b17b58a3de5a98d61349658dd8b58bc3bfa5b08ec98ecf6bb45447bc45497275645c6cc432bf191633578079fc8787b0ee849e5af9c9a60375da395a8f7fbb5bc80c876748e5e000aedc8de1e163bbb930f5f05f49eafdfe43407e1daa8be3a9a68d8aeb17e55e562ae2d9efc90e3ced7e9992663a98c4309703e68728dfe1ec72d08c5516592581f81e8f2d8b703331bfd313ad2e343f9c7a3548821ed079b6f019319b2f7c82937cb24e1a2fde130b23d72b7451a152f71e8576abddb9b0b135ad963dba00860e04a76e8930a74a5513734e50c724b5bd550aa3f06e9d61d236796e70e35026ab17007b95d82293a2aecb1f77af8ee6b448abddb2ddce73dbc52aab08791998257aa5e0736d60e8f2d7ae5b50ef48971836435fd81a8556e13ffad0889903995260194d5330f98205b61e5c6555d8404f97d9fba8c1b83ea7669c5df034056ce24efba683a1303a3a0596997fa29a5028c5c2c39d6e9f04e75babdc9087f61891173e05d73f05da01c36d28e73c3b5594b61c107";

        bytes32 earnerTokenRoot = 0x899e3bde2c009bda46a51ecacd5b3f6df0af2833168cc21cac5f75e8c610ce0d;
        IRewardsCoordinator.EarnerTreeMerkleLeaf memory earnerLeaf = IRewardsCoordinator.EarnerTreeMerkleLeaf({
            earner: deployer,
            earnerTokenRoot: earnerTokenRoot
        });

        uint32[] memory tokenIndices = new uint32[](2);
        tokenIndices[0] = 0;
        tokenIndices[1] = 1;

        bytes[] memory tokenTreeProofs = new bytes[](2);
        tokenTreeProofs[0] = hex"30c06778aea3c632bc61f3a0ffa0b57bd9ce9c2cf76f9ad2369f1b46081bc90b";
        tokenTreeProofs[1] = hex"c82aa805d0910fc0a12610e7b59a440050529cf2a5b9e5478642bfa7f785fc79";

        IRewardsCoordinator.TokenTreeMerkleLeaf[] memory tokenLeaves;
        tokenLeaves = new IRewardsCoordinator.TokenTreeMerkleLeaf[](2);
        tokenLeaves[0] = IRewardsCoordinator.TokenTreeMerkleLeaf({
            token: IERC20(0x4Bd30dAf919a3f74ec57f0557716Bcc660251Ec0),
            cumulativeEarnings: 3919643917052950253556
        });
        tokenLeaves[1] = IRewardsCoordinator.TokenTreeMerkleLeaf({
            token: IERC20(0xdeeeeE2b48C121e6728ed95c860e296177849932),
            cumulativeEarnings: 897463507533062629000000
        });

        IRewardsCoordinator.RewardsMerkleClaim memory claim = IRewardsCoordinator.RewardsMerkleClaim({
            rootIndex: 84, // uint32 rootIndex;
            earnerIndex: 66130, // uint32 earnerIndex;
            earnerTreeProof: earnerTreeProof, // bytes earnerTreeProof;
            earnerLeaf: earnerLeaf, // EarnerTreeMerkleLeaf earnerLeaf;
            tokenIndices: tokenIndices, // uint32[] tokenIndices;
            tokenTreeProofs: tokenTreeProofs, // bytes[] tokenTreeProofs;
            tokenLeaves: tokenLeaves // TokenTreeMerkleLeaf[] tokenLeaves;
        });

        address recipient = deployer;

        // sign the message for EigenAgent to execute Eigenlayer command
        bytes memory messageWithSignature_PC = signMessageForEigenAgentExecution(
            deployerKey,
            block.chainid, // destination chainid where EigenAgent lives
            address(123123), // StrategyManager to approve + deposit
            encodeProcessClaimMsg(claim, recipient),
            execNonce,
            expiry
        );

        (
            IRewardsCoordinator.RewardsMerkleClaim memory _claim,
            address _recipient,
            address _signer,
            uint256 _expiry,
            bytes memory _signature
        ) = eigenlayerMsgDecoders.decodeProcessClaimMsg(
            abi.encode(string(
                messageWithSignature_PC
            ))
        );

        require(claim.rootIndex == 84, "decodeProcessClaimMsg: rootIndex incorrect");
        require(claim.earnerIndex == 66130, "decodeProcessClaimMsg: earnerIndex incorrect");
        require(
            keccak256(claim.earnerTreeProof) == keccak256(earnerTreeProof),
            "decodeProcessClaimMsg: earnerTreeProof incorrect"
        );
        require(claim.earnerLeaf.earner == deployer, "decodeProcessClaimMsg: earnerLeaf.earner incorrect");
        require(claim.earnerLeaf.earnerTokenRoot == earnerTokenRoot, "decodeProcessClaimMsg: earnerLeaf.earnerTokenRoot incorrect");
        require(claim.tokenIndices[0] == 0, "decodeProcessClaimMsg: earnerLeaf.tokenIndices[0] incorrect");
        require(claim.tokenIndices[1] == 1, "decodeProcessClaimMsg: earnerLeaf.tokenIndices[1] incorrect");

        require(keccak256(claim.tokenTreeProofs[0]) == keccak256(tokenTreeProofs[0]),
            "decodeProcessClaimMsg: earnerLeaf.tokenTreeProofs[0] incorrect"
        );
        require(
            keccak256(claim.tokenTreeProofs[1]) == keccak256(tokenTreeProofs[1]),
            "decodeProcessClaimMsg: earnerLeaf.tokenTreeProofs[1] incorrect"
        );

        require(claim.tokenLeaves[0].token == tokenLeaves[0].token, "decodeProcessClaimMsg: earnerLeaf.tokenLeaves[0] incorrect");
        require(
            claim.tokenLeaves[0].cumulativeEarnings == tokenLeaves[0].cumulativeEarnings,
            "decodeProcessClaimMsg: tokenLeaves[0].cumulativeEarnings incorrect"
        );
        require(claim.tokenLeaves[1].token == tokenLeaves[1].token, "decodeProcessClaimMsg: earnerLeaf.tokenLeaves[1] incorrect");
        require(
            claim.tokenLeaves[1].cumulativeEarnings == tokenLeaves[1].cumulativeEarnings,
            "decodeProcessClaimMsg: tokenLeaves[1].cumulativeEarnings incorrect"
        );

        require(_signer == deployer, "decodeProcessClaimMsg: signer incorrect");
        require(_expiry == expiry, "decodeProcessClaimMsg: expiry incorrect");
    }
}
