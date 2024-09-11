// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";

import {
    EigenlayerMsgDecoders,
    DelegationDecoders,
    AgentOwnerSignature
} from "../src/utils/EigenlayerMsgDecoders.sol";
import {EigenlayerMsgEncoders} from "../src/utils/EigenlayerMsgEncoders.sol";

import {ClientEncoders} from "../script/ClientEncoders.sol";
import {ClientSigners} from "../script/ClientSigners.sol";
import {EthSepolia} from "../script/Addresses.sol";



contract ClientSignerEncoderTests is BaseTestEnvironment {

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

        setUpForkedEnvironment();

        amount = 0.0077 ether;
        staker = deployer;
        expiry = block.timestamp + 1 hours;
        execNonce = 0;

        operatorKey = uint256(88888);
        operator = vm.addr(operatorKey);

        operator2Key = uint256(99999);
        operator2 = vm.addr(operator2Key);

        vm.selectFork(ethForkId);
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

        clientSignersTest.checkSignature_EIP1271(signer, digestHash, signature);

        vm.assertEq(
            IERC1271.isValidSignature.selector,
            eigenAgent.isValidSignature(digestHash, signature)
        );
    }

    function test_ClientSigner_createEigenlayerDepositDigest() public view {

        bytes32 domainSeparator = clientSignersTest.domainSeparator(address(strategyManager), EthSepolia.ChainId);

        bytes32 digest1 = clientSignersTest.createEigenlayerDepositDigest(
            strategy,
            tokenL1,
            amount,
            staker,
            execNonce,
            expiry,
            domainSeparator
        );

        bytes32 DEPOSIT_TYPEHASH = keccak256("Deposit(address staker,address strategy,address token,uint256 amount,uint256 nonce,uint256 expiry)");
        bytes32 structHash = keccak256(abi.encode(
            DEPOSIT_TYPEHASH,
            staker,
            strategy,
            tokenL1,
            amount,
            execNonce,
            expiry
        ));
        bytes32 digest2 = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        vm.assertEq(digest1, digest2);
    }

    function test_ClientSigner_getDomainSeparator() public view {

        address contractAddr = address(strategyManager);
        uint256 chainid = EthSepolia.ChainId;
        bytes32 DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

        bytes32 domainSeparator1 = keccak256(abi.encode(
            DOMAIN_TYPEHASH,
            keccak256(bytes("EigenLayer")),
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
            domainSeparator(delegationManagerAddr, destinationChainid),
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
            _data,
            _nonce,
            _chainid,
            _expiry
        ));
        // calculate the digest hash
        bytes32 digestHash = keccak256(abi.encodePacked(
            "\x19\x01",
            domainSeparator(_target, _chainid),
            structHash
        ));

        bytes32 digestHash2 = clientSignersTest.createEigenAgentCallDigestHash(
            _target,
            _value,
            _data,
            _nonce,
            _chainid,
            _expiry
        );

        vm.assertEq(digestHash, digestHash2);
    }

    function test_ClientSigner_signMessageForEigenAgentExecution(
    ) public view returns (bytes memory) {

        uint256 signerKey = bobKey;
        uint256 chainid = EthSepolia.ChainId;
        address targetContractAddr = address(delegationManager);
        bytes memory messageToEigenlayer = abi.encodeWithSelector(0x11992233, 1233, "something");
        uint256 execNonceEigenAgent = 0;

        bytes memory messageWithSignature1;
        bytes memory signatureEigenAgent1;
        {
            bytes32 digestHash = createEigenAgentCallDigestHash(
                targetContractAddr,
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
                bytes32(abi.encode(signer)), // pad signer to 32byte word
                expiry,
                signatureEigenAgent1
            );
        }

        bytes memory messageWithSignature2 = clientSignersTest.signMessageForEigenAgentExecution(
            signerKey,
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

        IDelegationManager.QueuedWithdrawalParams[] memory QWPArray;
        QWPArray = new IDelegationManager.QueuedWithdrawalParams[](1);
        QWPArray[0] = IDelegationManager.QueuedWithdrawalParams({
            strategies: strategiesToWithdraw,
            shares: sharesToWithdraw,
            withdrawer: address(eigenAgent)
        });

        vm.assertEq(
            keccak256(clientEncodersTest.encodeQueueWithdrawalsMsg(QWPArray)),
            keccak256(EigenlayerMsgEncoders.encodeQueueWithdrawalsMsg(QWPArray))
        );
    }

    function makeMockWithdrawal() public view returns (
        IDelegationManager.Withdrawal memory
    ) {

        uint32 startBlock = uint32(block.number);

        IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
        uint256[] memory sharesToWithdraw = new uint256[](1);
        strategiesToWithdraw[0] = strategy;
        sharesToWithdraw[0] = amount;

        IDelegationManager.Withdrawal memory withdrawal = IDelegationManager.Withdrawal({
            staker: address(eigenAgent),
            delegatedTo: vm.addr(1222),
            withdrawer: address(eigenAgent),
            nonce: 0,
            startBlock: startBlock,
            strategies: strategiesToWithdraw,
            shares: sharesToWithdraw
        });

        return withdrawal;
    }

    function test_ClientEncoder_encodeCompleteWithdrawalMsg() public view {

        IDelegationManager.Withdrawal memory withdrawal = makeMockWithdrawal();

        IERC20[] memory tokensToWithdraw = new IERC20[](1);
        tokensToWithdraw[0] = tokenL1;
        uint256 middlewareTimesIndex = 0;
        bool receiveAsTokens = true;

        vm.assertEq(
            keccak256(abi.encode(
                clientEncodersTest.encodeCompleteWithdrawalMsg(
                    withdrawal,
                    tokensToWithdraw,
                    middlewareTimesIndex,
                    receiveAsTokens
                )
            )),
            keccak256(abi.encode(
                EigenlayerMsgEncoders.encodeCompleteWithdrawalMsg(
                    withdrawal,
                    tokensToWithdraw,
                    middlewareTimesIndex,
                    receiveAsTokens
                )
            ))
        );
    }

    function test_ClientEncoder_calculateWithdrawalTransferRoot() public view {

        IDelegationManager.Withdrawal memory withdrawal = makeMockWithdrawal();
        bytes32 withdrawalRoot = clientEncodersTest.calculateWithdrawalRoot(withdrawal);

        vm.assertEq(
            keccak256(abi.encode(
                clientEncodersTest.calculateWithdrawalTransferRoot(withdrawalRoot, amount, deployer)
            )),
            keccak256(abi.encode(
                EigenlayerMsgEncoders.calculateWithdrawalTransferRoot(withdrawalRoot, amount, deployer)
            ))
        );
    }

    function test_SenderHooks_calculateWithdrawalTransferRoot() public {

        IDelegationManager.Withdrawal memory withdrawal = makeMockWithdrawal();
        bytes32 withdrawalRoot = clientEncodersTest.calculateWithdrawalRoot(withdrawal);

        vm.selectFork(l2ForkId);

        vm.assertEq(
            keccak256(abi.encode(
                senderHooks.calculateWithdrawalTransferRoot(withdrawalRoot, amount, deployer)
            )),
            keccak256(abi.encode(
                EigenlayerMsgEncoders.calculateWithdrawalTransferRoot(withdrawalRoot, amount, deployer)
            ))
        );
    }

    function test_ClientEncoder_encodeHandleTransferToAgentOwnerMsg() public view {

        IDelegationManager.Withdrawal memory withdrawal = makeMockWithdrawal();
        bytes32 withdrawalRoot = clientEncodersTest.calculateWithdrawalRoot(withdrawal);
        bytes32 withdrawalTransferRoot = clientEncodersTest.calculateWithdrawalTransferRoot(
            withdrawalRoot,
            amount,
            deployer
        );

        vm.assertEq(
            keccak256(abi.encode(
                clientEncodersTest.encodeHandleTransferToAgentOwnerMsg(withdrawalTransferRoot)
            )),
            keccak256(abi.encode(
                EigenlayerMsgEncoders.encodeHandleTransferToAgentOwnerMsg(withdrawalTransferRoot)
            ))
        );
    }

    function test_ClientEncoder_encodeDelegateTo() public view {

        address eigenAgent = vm.addr(0x1);
        bytes32 approverSalt = 0x0000000000000000000000000000000000000000000000000000000000002346;
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

    function test_ClientEncoder_encodeMintEigenAgent() public view {
        vm.assertEq(
            keccak256(clientEncodersTest.encodeMintEigenAgent(bob)),
            keccak256(EigenlayerMsgEncoders.encodeMintEigenAgent(bob))
        );
    }
}
