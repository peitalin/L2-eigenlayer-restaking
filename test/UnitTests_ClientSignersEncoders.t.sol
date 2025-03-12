// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";

import {IERC20} from "@openzeppelin-v4-contracts/token/ERC20/IERC20.sol";
import {IERC1271} from "@openzeppelin-v5-contracts/interfaces/IERC1271.sol";
import {SignatureChecker} from "@openzeppelin-v5-contracts/utils/cryptography/SignatureChecker.sol";

import {IStrategy} from "@eigenlayer-contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IDelegationManagerTypes} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {IRewardsCoordinatorTypes} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {ISignatureUtilsMixinTypes} from "@eigenlayer-contracts/interfaces/ISignatureUtilsMixin.sol";
import {EIP712_DOMAIN_TYPEHASH} from "@eigenlayer-contracts/mixins/SignatureUtilsMixin.sol";
import {EIGENLAYER_VERSION} from "../script/1_deployMockEigenlayerContracts.s.sol";

import {
    EigenlayerMsgDecoders,
    DelegationDecoders,
    AgentOwnerSignature
} from "../src/utils/EigenlayerMsgDecoders.sol";
import {EigenlayerMsgEncoders} from "../src/utils/EigenlayerMsgEncoders.sol";
import {EigenAgent6551} from "../src/6551/EigenAgent6551.sol";

import {ClientEncoders} from "../script/ClientEncoders.sol";
import {ClientSigners} from "../script/ClientSigners.sol";
import {EthSepolia} from "../script/Addresses.sol";



contract UnitTests_ClientSignersEncoders is BaseTestEnvironment {

    EigenlayerMsgDecoders public eigenlayerMsgDecoders;
    ClientSigners public clientSignersTest;
    ClientEncoders public clientEncodersTest;

    uint256 operatorKey;
    address operator;

    uint256 operator2Key;
    address operator2;

    uint256 amount;
    address staker;
    uint256 expiry;
    uint256 execNonce;

    function setUp() public {

        setUpLocalEnvironment();

        amount = 0.0077 ether;
        staker = deployer;
        expiry = block.timestamp + 1 hours;
        execNonce = 0;

        operatorKey = uint256(88888);
        operator = vm.addr(operatorKey);

        operator2Key = uint256(99999);
        operator2 = vm.addr(operator2Key);

        vm.prank(deployer);
        eigenAgent = agentFactory.spawnEigenAgentOnlyOwner(deployer);

        eigenlayerMsgDecoders = new EigenlayerMsgDecoders();
        // test clientEncoders, create a new instance.
        clientSignersTest = new ClientSigners();
        clientEncodersTest = new ClientEncoders();
    }

    /*
     *
     *
     *             Tests
     *
     *
     */

    function test_ClientSigner_checkSignature_EIP1271() public view {

        bytes32 digestHash = keccak256(abi.encode(bob, alice, deployer));
        address signer = deployer;

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerKey, digestHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        SignatureChecker.isValidSignatureNow(signer, digestHash, signature);

        vm.assertEq(
            IERC1271.isValidSignature.selector,
            eigenAgent.isValidSignature(digestHash, signature)
        );
    }

    function test_ClientSigner_EigenAgentVersionMatches() public view {
        vm.assertEq(
            clientSignersTest.TREASURE_RESTAKING_VERSION(),
            EigenAgent6551(payable(address(eigenAgent))).TREASURE_RESTAKING_VERSION()
        );
    }

    function test_ClientSigner_getDomainSeparator() public view {

        address contractAddr = address(strategyManager);
        uint256 chainid = EthSepolia.ChainId;
        bytes memory v = bytes(EIGENLAYER_VERSION);
        string memory majorVerion = string(bytes.concat(v[0], v[1]));

        bytes32 domainSeparator1 = keccak256(abi.encode(
            EIP712_DOMAIN_TYPEHASH,
            keccak256(bytes("EigenLayer")),
            keccak256(bytes(majorVerion)),
            chainid,
            contractAddr
        ));

        bytes32 domainSeparator2 = clientSignersTest.domainSeparator(contractAddr, chainid);

        vm.assertEq(domainSeparator1, domainSeparator2);
    }

    function test_ClientSigner_calculateDelegationApprovalDigestHash() public view {

        /// @notice The EIP-712 typehash for the `DelegationApproval` struct used by the contract
        bytes32 DELEGATION_APPROVAL_TYPEHASH = keccak256(
            "DelegationApproval(address delegationApprover,address staker,address operator,bytes32 salt,uint256 expiry)"
        );

        bytes32 approverSalt = bytes32(uint256(222222));
        address delegationManagerAddr = address(delegationManager);
        uint256 destinationChainid = EthSepolia.ChainId;

        // calculate the struct hash
        bytes32 approverStructHash = keccak256(
            abi.encode(DELEGATION_APPROVAL_TYPEHASH,
                operator, // _delegationApprover,
                address(eigenAgent), // staker == msg.sender == eigenAgent from Eigenlayer's perspective
                operator, // operator
                approverSalt,
                expiry
            )
        );
        // calculate the digest hash
        bytes32 approverDigestHash = keccak256(abi.encodePacked(
            "\x19\x01",
            clientSignersTest.domainSeparator(delegationManagerAddr, destinationChainid),
            approverStructHash
        ));

        bytes32 digestHash1 = clientSignersTest.calculateDelegationApprovalDigestHash(
            address(eigenAgent), // staker == msg.sender == eigenAgent from Eigenlayer's perspective
            operator, // operator
            operator, // _delegationApprover,
            approverSalt,
            expiry,
            delegationManagerAddr,
            destinationChainid
        );

        vm.assertEq(digestHash1, approverDigestHash);
    }

    function test_ClientSigner_createEigenAgentCallDigestHash() public {

        address _target = vm.addr(1);
        uint256 _value = 0 ether;
        bytes memory _data = abi.encodeWithSelector(0x11992233, 1233, "something");
        uint256 _nonce = 0;
        uint256 _chainid = EthSepolia.ChainId;
        uint256 _expiry = expiry;

        bytes32 structHash = keccak256(abi.encode(
            eigenAgent.EIGEN_AGENT_EXEC_TYPEHASH(),
            _target,
            _value,
            keccak256(_data),
            _nonce,
            _chainid,
            _expiry
        ));
        // calculate the digest hash
        bytes32 digestHash = keccak256(abi.encodePacked(
            "\x19\x01",
            clientSignersTest.domainSeparatorEigenAgent(address(eigenAgent), _chainid),
            structHash
        ));

        bytes32 digestHash2 = clientSignersTest.createEigenAgentCallDigestHash(
            _target,
            address(eigenAgent),
            _value,
            _data,
            _nonce,
            _chainid,
            _expiry
        );

        vm.assertEq(digestHash, digestHash2);
    }

    function test_ClientSigner_signMessageForEigenAgentExecution()
        public view returns (bytes memory)
    {

        uint256 signerKey = bobKey;
        uint256 chainid = EthSepolia.ChainId;
        address targetContractAddr = address(delegationManager);
        bytes memory messageToEigenlayer = abi.encodeWithSelector(0x11992233, 1233, "something");
        uint256 execNonceEigenAgent = 0;

        bytes memory messageWithSignature1;
        bytes memory signatureEigenAgent1;
        {
            bytes32 digestHash = clientSignersTest.createEigenAgentCallDigestHash(
                targetContractAddr,
                address(eigenAgent),
                0 ether, // not sending ether
                messageToEigenlayer,
                execNonceEigenAgent,
                chainid, // destination chainid where EigenAgent lives, usually ETH
                expiry
            );

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digestHash);
            signatureEigenAgent1 = abi.encodePacked(r, s, v);
            address signer = vm.addr(signerKey);

            messageWithSignature1 = abi.encodePacked(
                messageToEigenlayer,
                bytes32(abi.encode(signer)), // AgentOwner. Pad signer to 32byte word
                expiry,
                signatureEigenAgent1
            );
        }

        bytes memory messageWithSignature2 = clientSignersTest.signMessageForEigenAgentExecution(
            signerKey,
            address(eigenAgent),
            chainid,
            targetContractAddr,
            messageToEigenlayer,
            execNonceEigenAgent,
            expiry
        );

        vm.assertEq(keccak256(messageWithSignature1), keccak256(messageWithSignature2));
    }


    function test_ClientEncoder_encodeDepositIntoStrategyMsg() public view {

        address _strategy = address(strategy);
        address _tokenL1 = address(tokenL1 );

        vm.assertEq(
            keccak256(clientEncodersTest.encodeDepositIntoStrategyMsg(_strategy, _tokenL1, amount)),
            keccak256(EigenlayerMsgEncoders.encodeDepositIntoStrategyMsg(_strategy, _tokenL1, amount))
        );
    }

    function test_ClientEncoder_encodeQueueWithdrawalsMsg() public view {

        IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
        uint256[] memory sharesToWithdraw = new uint256[](1);
        strategiesToWithdraw[0] = strategy;
        sharesToWithdraw[0] = amount;

        IDelegationManagerTypes.QueuedWithdrawalParams[] memory QWPArray;
        QWPArray = new IDelegationManagerTypes.QueuedWithdrawalParams[](1);
        QWPArray[0] = IDelegationManagerTypes.QueuedWithdrawalParams({
            strategies: strategiesToWithdraw,
            depositShares: sharesToWithdraw,
            __deprecated_withdrawer: address(eigenAgent)
        });

        vm.assertEq(
            keccak256(clientEncodersTest.encodeQueueWithdrawalsMsg(QWPArray)),
            keccak256(EigenlayerMsgEncoders.encodeQueueWithdrawalsMsg(QWPArray))
        );
    }

    function makeMockWithdrawal() public view returns (
        IDelegationManagerTypes.Withdrawal memory
    ) {

        uint32 startBlock = uint32(block.number);

        IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
        uint256[] memory sharesToWithdraw = new uint256[](1);
        strategiesToWithdraw[0] = strategy;
        sharesToWithdraw[0] = amount;

        IDelegationManagerTypes.Withdrawal memory withdrawal = IDelegationManagerTypes.Withdrawal({
            staker: address(eigenAgent),
            delegatedTo: vm.addr(1222),
            withdrawer: address(eigenAgent),
            nonce: 0,
            startBlock: startBlock,
            strategies: strategiesToWithdraw,
            scaledShares: sharesToWithdraw
        });

        return withdrawal;
    }

    function test_ClientEncoder_encodeCompleteWithdrawalMsg() public view {

        IDelegationManagerTypes.Withdrawal memory withdrawal = makeMockWithdrawal();

        IERC20[] memory tokensToWithdraw = new IERC20[](1);
        tokensToWithdraw[0] = tokenL1;
        bool receiveAsTokens = true;

        vm.assertEq(
            keccak256(abi.encode(
                clientEncodersTest.encodeCompleteWithdrawalMsg(
                    withdrawal,
                    tokensToWithdraw,
                    receiveAsTokens
                )
            )),
            keccak256(abi.encode(
                EigenlayerMsgEncoders.encodeCompleteWithdrawalMsg(
                    withdrawal,
                    tokensToWithdraw,
                    receiveAsTokens
                )
            ))
        );
    }

    function test_ClientEncoder_encodeCompleteWithdrawals_ArrayMsg() public view {

        IDelegationManagerTypes.Withdrawal[] memory withdrawals = new IDelegationManagerTypes.Withdrawal[](1);
        withdrawals[0] = makeMockWithdrawal();

        IERC20[][] memory tokensToWithdraw = new IERC20[][](1);
        IERC20[] memory tokens1 = new IERC20[](1);
        tokens1[0] = IERC20(address(1));
        tokensToWithdraw[0] = tokens1;

        bool[] memory receiveAsTokens = new bool[](1);
        receiveAsTokens[0] = false;

        vm.assertEq(
            keccak256(abi.encode(
                clientEncodersTest.encodeCompleteWithdrawalsMsg(
                    withdrawals,
                    tokensToWithdraw,
                    receiveAsTokens
                )
            )),
            keccak256(abi.encode(
                EigenlayerMsgEncoders.encodeCompleteWithdrawalsMsg(
                    withdrawals,
                    tokensToWithdraw,
                    receiveAsTokens
                )
            ))
        );
    }

    function test_ClientEncoder_encodeTransferToAgentOwnerMsg() public view {
        vm.assertEq(
            keccak256(abi.encode(
                clientEncodersTest.encodeTransferToAgentOwnerMsg(deployer)
            )),
            keccak256(abi.encode(
                EigenlayerMsgEncoders.encodeTransferToAgentOwnerMsg(deployer)
            ))
        );
    }

    function test_ClientEncoder_encodeDelegateTo() public view {

        address eigenAgent = vm.addr(0x1);
        bytes32 approverSalt = 0x0000000000000000000000000000000000000000000000000000000000002346;
        uint256 sig1_expiry = block.timestamp + 50 minutes;

        ISignatureUtilsMixinTypes.SignatureWithExpiry memory approverSignatureAndExpiry;
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

            approverSignatureAndExpiry = ISignatureUtilsMixinTypes.SignatureWithExpiry({
                signature: signature1,
                expiry: sig1_expiry
            });
        }

        vm.assertEq(
            keccak256(abi.encode(
                clientEncodersTest.encodeDelegateTo(
                    operator,
                    approverSignatureAndExpiry,
                    approverSalt
                )
            )),
            keccak256(abi.encode(
                EigenlayerMsgEncoders.encodeDelegateTo(
                    operator,
                    approverSignatureAndExpiry,
                    approverSalt
                )
            ))
        );
    }

    function test_ClientEncoder_encodeUndelegateMsg() public view {
        vm.assertEq(
            keccak256(clientEncodersTest.encodeUndelegateMsg(bob)),
            keccak256(EigenlayerMsgEncoders.encodeUndelegateMsg(bob))
        );
    }

    function test_ClientEncoder_encodeMintEigenAgentMsg() public view {
        vm.assertEq(
            keccak256(clientEncodersTest.encodeMintEigenAgentMsg(bob)),
            keccak256(EigenlayerMsgEncoders.encodeMintEigenAgentMsg(bob))
        );
    }

    function makeMockRewardsMerkleClaim() public view returns (
        IRewardsCoordinator.RewardsMerkleClaim memory
    ) {

        bytes memory earnerTreeProof = hex"32c3756cc20bcbdb7f8b25dcb3b904ea271776626d79cf1797932298c3bc5c628a09335bd33183649a1338e1ce19dcc11b6e7500659b71ddeb3680855b6eeffdd879bbbe67f12fc80b7df9df2966012d54b23b2c1265c708cc64b12d38acf88a82277145d984d6a9dc5bdfa13cee09e543b810cef077330bd5828b746b8c92bb622731e95bf8721578fa6c5e1ceaf2e023edb2b9c989c7106af8455ceae4aaad1891758b2b17b58a3de5a98d61349658dd8b58bc3bfa5b08ec98ecf6bb45447bc45497275645c6cc432bf191633578079fc8787b0ee849e5af9c9a60375da395a8f7fbb5bc80c876748e5e000aedc8de1e163bbb930f5f05f49eafdfe43407e1daa8be3a9a68d8aeb17e55e562ae2d9efc90e3ced7e9992663a98c4309703e68728dfe1ec72d08c5516592581f81e8f2d8b703331bfd313ad2e343f9c7a3548821ed079b6f019319b2f7c82937cb24e1a2fde130b23d72b7451a152f71e8576abddb9b0b135ad963dba00860e04a76e8930a74a5513734e50c724b5bd550aa3f06e9d61d236796e70e35026ab17007b95d82293a2aecb1f77af8ee6b448abddb2ddce73dbc52aab08791998257aa5e0736d60e8f2d7ae5b50ef48971836435fd81a8556e13ffad0889903995260194d5330f98205b61e5c6555d8404f97d9fba8c1b83ea7669c5df034056ce24efba683a1303a3a0596997fa29a5028c5c2c39d6e9f04e75babdc9087f61891173e05d73f05da01c36d28e73c3b5594b61c107";

        bytes32 earnerTokenRoot = 0x899e3bde2c009bda46a51ecacd5b3f6df0af2833168cc21cac5f75e8c610ce0d;
        IRewardsCoordinatorTypes.EarnerTreeMerkleLeaf memory earnerLeaf = IRewardsCoordinatorTypes.EarnerTreeMerkleLeaf({
            earner: deployer,
            earnerTokenRoot: earnerTokenRoot
        });

        uint32[] memory tokenIndices = new uint32[](2);
        tokenIndices[0] = 0;
        tokenIndices[1] = 1;

        bytes[] memory tokenTreeProofs = new bytes[](2);
        tokenTreeProofs[0] = hex"30c06778aea3c632bc61f3a0ffa0b57bd9ce9c2cf76f9ad2369f1b46081bc90b";
        tokenTreeProofs[1] = hex"c82aa805d0910fc0a12610e7b59a440050529cf2a5b9e5478642bfa7f785fc79";

        IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[] memory tokenLeaves;
        tokenLeaves = new IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[](2);
        tokenLeaves[0] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(0x4Bd30dAf919a3f74ec57f0557716Bcc660251Ec0),
            cumulativeEarnings: 3919643917052950253556
        });
        tokenLeaves[1] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(0xdeeeeE2b48C121e6728ed95c860e296177849932),
            cumulativeEarnings: 897463507533062629000000
        });

        IRewardsCoordinatorTypes.RewardsMerkleClaim memory claim = IRewardsCoordinatorTypes.RewardsMerkleClaim({
            rootIndex: 84, // uint32 rootIndex;
            earnerIndex: 66130, // uint32 earnerIndex;
            earnerTreeProof: earnerTreeProof, // bytes earnerTreeProof;
            earnerLeaf: earnerLeaf, // EarnerTreeMerkleLeaf earnerLeaf;
            tokenIndices: tokenIndices, // uint32[] tokenIndices;
            tokenTreeProofs: tokenTreeProofs, // bytes[] tokenTreeProofs;
            tokenLeaves: tokenLeaves // TokenTreeMerkleLeaf[] tokenLeaves;
        });

        return claim;
    }

    function test_ClientEncoder_encodeRewardsTransferToAgentOwnerMsg() public view {

        address agentOwner = deployer;

        vm.assertEq(
            keccak256(abi.encode(
                clientEncodersTest.encodeTransferToAgentOwnerMsg(agentOwner)
            )),
            keccak256(abi.encode(
                EigenlayerMsgEncoders.encodeTransferToAgentOwnerMsg(agentOwner)
            ))
        );
    }

}
