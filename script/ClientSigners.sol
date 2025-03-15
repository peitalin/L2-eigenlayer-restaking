//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {SignatureChecker} from "@openzeppelin-v5-contracts/utils/cryptography/SignatureChecker.sol";
import {IStrategy} from "@eigenlayer-contracts/interfaces/IStrategy.sol";
import {EIGENLAYER_VERSION} from "./1_deployMockEigenlayerContracts.s.sol";
import {EIP712_DOMAIN_TYPEHASH} from "@eigenlayer-contracts/mixins/SignatureUtilsMixin.sol";
import {Strings} from "@openzeppelin-v5-contracts/utils/Strings.sol";

/// @dev Retrieve these struct hashes by calling Eigenlayer contracts, or storing the hash.
contract ClientSigners is Script {

    /// @notice The EIP-712 typehash for the deposit struct used by the contract
    bytes32 public constant EIGEN_AGENT_EXEC_TYPEHASH = keccak256(
        "ExecuteWithSignature(address target,uint256 value,bytes data,uint256 execNonce,uint256 chainId,uint256 expiry)"
    );

    /// @notice EigenAgent version
    string public constant TREASURE_RESTAKING_VERSION = "v1.0.0";

    /*
     *
     *            Eigenlayer Signatures
     *
     */

    /// @dev domainSeparator as per: eigenlayer-contracts/src/contracts/mixins/SignatureUtilsMixin.sol
    /// @notice This function is used to calculate the domainSeparator for calls to Eigenlayer contracts
    /// that require signatures (delegation approvals for instance)
    function domainSeparator(
        address contractAddr,
        uint256 destinationChainid
    ) public pure returns (bytes32) {
        uint256 chainid = destinationChainid;
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("EigenLayer")),
                keccak256(bytes(_majorVersion(EIGENLAYER_VERSION))),
                chainid,
                contractAddr
            )
        );
        // Note: in calculating the domainSeparator:
        // contractAddr is the target contract validating the signature, not this contract (ClientSigners)
        // e.g the DepositManager, or StrategyManager.
        // chainid should be destination chainid in the context of L2 -> L1 restaking calls
    }

    /// @notice Returns the major version of the contract. See Eigenlayer SemVerMixin.sol
    /// @return The major version string (e.g., "v1" for version "v1.2.3")
    function _majorVersion(string memory _version) internal pure returns (string memory) {
        bytes memory v = bytes(_version);
        return string(bytes.concat(v[0], v[1]));
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
        bytes32 approverStructHash = keccak256(
            abi.encode(DELEGATION_APPROVAL_TYPEHASH, _delegationApprover, staker, operator, approverSalt, expiry)
        );
        bytes32 approverDigestHash = keccak256(abi.encodePacked(
            "\x19\x01",
            domainSeparator(delegationManagerAddr, destinationChainid),
            approverStructHash
        ));
        return approverDigestHash;
    }

    /*
     *
     *            Treasure EigenAgent Signatures
     *
     */

    function createEigenAgentCallDigestHash(
        address _target,
        address _eigenAgent,
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
            keccak256(_data),
            _nonce,
            _chainid,
            _expiry
        ));
        // calculate the digest hash
        bytes32 digestHash = keccak256(abi.encodePacked(
            "\x19\x01",
            domainSeparatorEigenAgent(_eigenAgent, _chainid),
            structHash
        ));

        // Conform with EIP-191 for frontend clients
        digestHash = hashDigest191(digestHash);

        return digestHash;
    }

    /// @notice This function is used to calculate the domainSeparator calls to EigenAgent
    function domainSeparatorEigenAgent(
        address contractAddr,
        uint256 destinationChainid
    ) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("EigenAgent")),
                keccak256(bytes(_majorVersionEigenAgent())),
                destinationChainid,
                contractAddr
            )
        );
        // Note: in calculating the domainSeparator:
        // contractAddr is the target contract validating the signature, not this contract (ClientSigners)
        // e.g the EigenAgent address
    }

    /// @notice Returns the major version of the contract. See Eigenlayer SemVerMixin.sol
    /// @return The major version string (e.g., "v1" for version "v1.2.3")
    function _majorVersionEigenAgent() internal pure returns (string memory) {
        bytes memory v = bytes(TREASURE_RESTAKING_VERSION);
        return string(bytes.concat(v[0], v[1]));
    }

    struct EigenAgentExecution {
        uint256 chainid;
        address targetContractAddr;
        bytes messageToEigenlayer;
        uint256 execNonceEigenAgent;
        uint256 expiry;
    }

    function signMessageForEigenAgentExecution(
        uint256 signerKey,
        address eigenAgentAddr,
        uint256 chainid,
        address targetContractAddr,
        bytes memory messageToEigenlayer,
        uint256 execNonceEigenAgent,
        uint256 expiry
    ) public view returns (bytes memory) {

        require(targetContractAddr != address(0x0), "ClientSigner: targetContract cannot be 0x0");
        require(eigenAgentAddr != address(0x0), "ClientSigner: eigenAgent cannot be 0x0");
        require(chainid != 0, "ClientSigner: chainid cannot be 0");

        bytes memory messageWithSignature;
        bytes memory signatureEigenAgent;
        {
            bytes32 digestHash = createEigenAgentCallDigestHash(
                targetContractAddr,
                eigenAgentAddr,
                0 ether, // not sending ether
                messageToEigenlayer,
                execNonceEigenAgent,
                chainid, // destination chainid where EigenAgent lives: L1 Ethereum
                expiry
            );

            {
                (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digestHash);
                signatureEigenAgent = abi.encodePacked(r, s, v);
            }

            // Join the payload + signer + expiry + signature
            // NOTE: the order:
            // 1: message
            // 2: signer
            // 3: expiry
            // 4: signature

            messageWithSignature = abi.encodePacked(
                messageToEigenlayer,
                bytes32(abi.encode(vm.addr(signerKey))), // AgentOwner. Pad signer to 32byte word
                expiry,
                signatureEigenAgent
            );

            _logClientEigenAgentExecutionMessage(chainid, eigenAgentAddr, targetContractAddr, messageToEigenlayer, execNonceEigenAgent, expiry);
            _logClientSignature(vm.addr(signerKey), digestHash, signatureEigenAgent);
            SignatureChecker.isValidSignatureNow(vm.addr(signerKey), digestHash, signatureEigenAgent);
        }

        return messageWithSignature;
    }

    function _logClientEigenAgentExecutionMessage(
        uint256 chainid,
        address eigenAgentAddr,
        address targetContractAddr,
        bytes memory messageToEigenlayer,
        uint256 execNonce,
        uint256 expiry
    ) private pure {
        console.log("===== EigenAgent Signature =====");
        console.log("targetContractAddr:", targetContractAddr);
        console.log("eigenAgent:", eigenAgentAddr);
        console.log("messageToEigenlayer:");
        console.logBytes(messageToEigenlayer);
        // foundry v1.01 console.log is broken, does not log uints even with this fix:
        // https://github.com/foundry-rs/foundry/issues/9959
        // Use v0.3.0 to log expiry, execNonce, chainid
        // foundryup --use stable
        // foundryup --use v0.3.0
        console.log("execNonce:", uint256(execNonce));
        console.log("chainid:", uint256(chainid));
        console.log("expiry:", uint256(expiry));
        console.log("--------------------------------");
    }

    function _logClientSignature(address signer, bytes32 digestHash, bytes memory signatureEigenAgent) private pure {
        console.log("agentOwner/signer:", signer);
        console.log("digestHash:");
        console.logBytes32(digestHash);
        console.log("signature:");
        console.logBytes(signatureEigenAgent);
        console.log("================================");
    }

    function hashDigest191(bytes32 message) internal pure returns (bytes32) {
        // Follow EIP-191 format for personal_sign
        return keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            message
        ));
    }
}

