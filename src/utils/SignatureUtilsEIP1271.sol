//SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EIP1271SignatureUtils} from "eigenlayer-contracts/src/contracts/libraries/EIP1271SignatureUtils.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";


contract SignatureUtilsEIP1271 {

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
        address strategyManagerAddr,
        uint256 destinationChainid
    ) public pure returns (bytes32) {
        return calculateDomainSeparator(strategyManagerAddr, destinationChainid);
    }

    function calculateDomainSeparator(
        address strategyManagerAddr,
        uint256 destinationChainid
    ) public pure returns (bytes32) {

        /// @notice The EIP-712 typehash for the contract's domain
        bytes32 DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

        uint256 chainid = destinationChainid;

        return keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes("EigenLayer")), chainid, strategyManagerAddr));

        // Note: in calculating the domainSeparator:
        // address(this) is the StrategyManager, not this contract (SignatureUtilsEIP2172)
        // chainid is the chain Eigenlayer was deployed on, not the chain from which you are calling this function
        // so chainid should be destination chainid in the context of L2 -> L2 restaking calls
    }
}
