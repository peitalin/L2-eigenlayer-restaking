//SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EIP1271SignatureUtils} from "eigenlayer-contracts/src/contracts/libraries/EIP1271SignatureUtils.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";


/// @dev Retrieve these struct hashes by calling Eigenlayer contracts, or storing the hash.
contract SignatureUtilsEIP1271 is Script {

    /*
     *
     *            Constants
     *
     */

    /// @notice The EIP-712 typehash for the deposit struct used by the contract
    bytes32 public constant EIGEN_AGENT_EXEC_TYPEHASH = keccak256("ExecuteWithSignature(address target, uint256 value, bytes data, uint256 expiry)");

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

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
        EIP1271SignatureUtils.checkSignature_EIP1271(signer, digestHash, signature);
    }

    function createEigenlayerDepositDigest(
        IStrategy strategy,
        IERC20 token,
        uint256 amount,
        address staker,
        uint256 nonce,
        uint256 expiry,
        bytes32 domainSeparator
    ) public pure returns (bytes32) {

        /// @notice The EIP-712 typehash for the deposit struct used by the contract
        bytes32 DEPOSIT_TYPEHASH = keccak256("Deposit(address staker,address strategy,address token,uint256 amount,uint256 nonce,uint256 expiry)");

        bytes32 structHash = keccak256(abi.encode(DEPOSIT_TYPEHASH, staker, strategy, token, amount, nonce, expiry));
        // calculate the digest hash
        bytes32 digestHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        return digestHash;
    }

    function getDomainSeparator(
        address contractAddr, // strategyManagerAddr, or delegationManagerAddr
        uint256 destinationChainid
    ) public pure returns (bytes32) {

        uint256 chainid = destinationChainid;

        return keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes("EigenLayer")), chainid, contractAddr));
        // Note: in calculating the domainSeparator:
        // address(this) is the StrategyManager, not this contract (SignatureUtilsEIP2172)
        // chainid is the chain Eigenlayer is deployed on (it can fork!), not the chain you are calling this function
        // So chainid should be destination chainid in the context of L2 -> L1 restaking calls
    }

    function calculateQueueWithdrawalDigestHash(
        address staker,
        IStrategy[] memory strategies,
        uint256[] memory shares,
        uint256 withdrawalNonce,
        uint256 expiry,
        address delegationManagerAddr,
        uint256 destinationChainid
    ) public pure returns (bytes32) {

        /// @notice The EIP-712 typehash for the deposit struct used by the contract
        bytes32 QUEUE_WITHDRAWAL_TYPEHASH =
            keccak256("QueueWithdrawal(address staker,address[] strategies,uint256[] shares,uint256 nonce,uint256 expiry)");

        // calculate the struct hash
        bytes32 structHash = keccak256(abi.encode(
            QUEUE_WITHDRAWAL_TYPEHASH,
            staker,
            strategies,
            shares,
            withdrawalNonce,
            expiry
        ));
        // calculate the digest hash
        bytes32 digestHash = keccak256(abi.encodePacked(
            "\x19\x01",
            getDomainSeparator(delegationManagerAddr, destinationChainid),
            structHash
        ));
        return digestHash;
    }

    function calculateStakerDelegationDigestHash(
        address staker,
        uint256 _stakerNonce,
        address operator,
        uint256 expiry,
        address delegationManagerAddr,
        uint256 destinationChainid
    ) public pure returns (bytes32) {

        /// @notice The EIP-712 typehash for the `StakerDelegation` struct used by the contract
        bytes32 STAKER_DELEGATION_TYPEHASH =
            keccak256("StakerDelegation(address staker,address operator,uint256 nonce,uint256 expiry)");

        // calculate the struct hash
        bytes32 stakerStructHash =
            keccak256(abi.encode(STAKER_DELEGATION_TYPEHASH, staker, operator, _stakerNonce, expiry));
        // calculate the digest hash
        bytes32 stakerDigestHash = keccak256(abi.encodePacked(
            "\x19\x01",
            getDomainSeparator(delegationManagerAddr, destinationChainid),
            stakerStructHash
        ));
        return stakerDigestHash;
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
            getDomainSeparator(delegationManagerAddr, destinationChainid),
            approverStructHash
        ));
        return approverDigestHash;
    }

    function createEigenAgentCallDigestHash(
        address _target,
        uint256 _value,
        bytes calldata _data,
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
            getDomainSeparator(_target, _chainid),
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
    ) returns (
        bytes memory,
        bytes memory
    ) {
        // sign the message for EigenAgent
        bytes32 digestHash = createEigenAgentCallDigestHash(
            targetContractAddr,
            0 ether, // not sending ether
            messageToEigenlayer,
            execNonceEigenAgent,
            chainid, // destination chainid where EigenAgent lives, usually ETH
            expiry
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digestHash);
        bytes memory signatureEigenAgent = abi.encodePacked(r, s, v);

        // NOTE: abi.encodePacked to join the payload + expiry + signature
        bytes memory messageWithSignature = abi.encodePacked(
            messageToEigenlayer,
            expiry,
            signatureEigenAgent
        );

        checkSignature_EIP1271(vm.addr(signerKey), digestHash, signatureEigenAgent);

        return (
            signatureEigenAgent,
            messageWithSignature
        );
    }

}
