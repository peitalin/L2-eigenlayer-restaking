//SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SignatureChecker} from "@openzeppelin-v5/contracts/utils/cryptography/SignatureChecker.sol";
import {IStrategy} from "@eigenlayer-contracts/interfaces/IStrategy.sol";


/// @dev Retrieve these struct hashes by calling Eigenlayer contracts, or storing the hash.
contract ClientSigners is Script {

    /*
     *
     *            Constants
     *
     */

    /// @notice The EIP-712 typehash for the deposit struct used by the contract
    bytes32 public constant EIGEN_AGENT_EXEC_TYPEHASH = keccak256(
        "ExecuteWithSignature(address target,uint256 value,bytes data,uint256 execNonce,uint256 chainId,uint256 expiry)"
    );

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,uint256 chainId,address verifyingContract)"
    );

    /*
     *
     *            Functions
     *
     */

    function checkSignature_EIP1271(
        address signer,
        bytes32 digestHash,
        bytes memory signature
    ) public view {
        SignatureChecker.isValidSignatureNow(signer, digestHash, signature);
    }

    function createEigenlayerDepositDigest(
        IStrategy strategy,
        IERC20 token,
        uint256 amount,
        address staker,
        uint256 nonce,
        uint256 expiry,
        bytes32 _domainSeparator
    ) public pure returns (bytes32) {

        /// @notice The EIP-712 typehash for the deposit struct used by the contract
        bytes32 DEPOSIT_TYPEHASH = keccak256("Deposit(address staker,address strategy,address token,uint256 amount,uint256 nonce,uint256 expiry)");

        bytes32 structHash = keccak256(abi.encode(DEPOSIT_TYPEHASH, staker, strategy, token, amount, nonce, expiry));
        // calculate the digest hash
        bytes32 digestHash = keccak256(abi.encodePacked("\x19\x01", _domainSeparator, structHash));

        return digestHash;
    }

    function domainSeparator(
        address contractAddr, // strategyManagerAddr, or delegationManagerAddr
        uint256 destinationChainid
    ) public pure returns (bytes32) {

        uint256 chainid = destinationChainid;

        return keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes("EigenLayer")), chainid, contractAddr));
        // Note: in calculating the domainSeparator:
        // address(this) is the StrategyManager, not this contract (SignatureUtils)
        // chainid is the chain Eigenlayer is deployed on (it can fork!), not the chain you are calling this function
        // So chainid should be destination chainid in the context of L2 -> L1 restaking calls
    }

    function calculateDelegationApprovalDigestHash(
        address staker,
        address operator,
        address _delegationApprover,
        bytes32 approverSalt,
        uint256 expiry,
        address delegationManagerAddr,
        uint256 destinationChainid
    ) public pure returns (bytes32) {

        /// @notice The EIP-712 typehash for the `DelegationApproval` struct used by the contract
        bytes32 DELEGATION_APPROVAL_TYPEHASH = keccak256(
            "DelegationApproval(address delegationApprover,address staker,address operator,bytes32 salt,uint256 expiry)"
        );

        // calculate the struct hash
        bytes32 approverStructHash = keccak256(
            abi.encode(DELEGATION_APPROVAL_TYPEHASH, _delegationApprover, staker, operator, approverSalt, expiry)
        );
        // calculate the digest hash
        bytes32 approverDigestHash = keccak256(abi.encodePacked(
            "\x19\x01",
            domainSeparator(delegationManagerAddr, destinationChainid),
            approverStructHash
        ));
        return approverDigestHash;
    }

    function createEigenAgentCallDigestHash(
        address _target,
        uint256 _value,
        bytes memory _data,
        uint256 _nonce,
        uint256 _chainid,
        uint256 _expiry
    ) public pure returns (bytes32) {

        bytes32 structHash = keccak256(abi.encode(
            EIGEN_AGENT_EXEC_TYPEHASH,
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

        return digestHash;
    }

    function signMessageForEigenAgentExecution(
        uint256 signerKey,
        uint256 chainid,
        address targetContractAddr,
        bytes memory messageToEigenlayer,
        uint256 execNonceEigenAgent,
        uint256 expiry
    ) public view returns (bytes memory) {

        require(targetContractAddr != address(0x0), "ClientSigner: targetContract cannot be 0x0");

        bytes memory messageWithSignature;
        bytes memory signatureEigenAgent;
        {
            bytes32 digestHash = createEigenAgentCallDigestHash(
                targetContractAddr,
                0 ether, // not sending ether
                messageToEigenlayer,
                execNonceEigenAgent,
                chainid, // destination chainid where EigenAgent lives: L1 Ethereum
                expiry
            );

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digestHash);
            signatureEigenAgent = abi.encodePacked(r, s, v);
            address signer = vm.addr(signerKey);

            // Join the payload + signer + expiry + signature
            // NOTE: the order:
            // 1: message
            // 2: signer
            // 3: expiry
            // 4: signature
            messageWithSignature = abi.encodePacked(
                messageToEigenlayer,
                bytes32(abi.encode(signer)), // pad signer to 32byte word
                expiry,
                signatureEigenAgent
            );

            _logClientEigenAgentExecutionMessage(chainid, targetContractAddr, messageToEigenlayer, execNonceEigenAgent, expiry);
            _logClientSignature(signer, digestHash, signatureEigenAgent);
            checkSignature_EIP1271(signer, digestHash, signatureEigenAgent);
        }

        return messageWithSignature;
    }

    function _logClientEigenAgentExecutionMessage(
        uint256 chainid,
        address targetContractAddr,
        bytes memory messageToEigenlayer,
        uint256 execNonce,
        uint256 expiry
    ) private pure {
        console.log("===== EigenAgent Signature =====");
        console.log("chainid:", chainid);
        console.log("targetContractAddr:", targetContractAddr);
        console.log("messageToEigenlayer:");
        console.logBytes(messageToEigenlayer);
        console.log("execNonce:", execNonce);
        console.log("expiry:", expiry);
        console.log("--------------------------------");
    }

    function _logClientSignature(address signer, bytes32 digestHash, bytes memory signatureEigenAgent) private pure {
        console.log("signer:", signer);
        console.log("digestHash:");
        console.logBytes32(digestHash);
        console.log("signature:");
        console.logBytes(signatureEigenAgent);
        console.log("================================");
    }
}
