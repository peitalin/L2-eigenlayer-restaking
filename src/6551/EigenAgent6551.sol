// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SignatureChecker} from "@openzeppelin-v5/contracts/utils/cryptography/SignatureChecker.sol";
import {ERC6551Account as ERC6551} from "@6551/examples/simple/ERC6551Account.sol";

import {IEigenAgentOwner721} from "./IEigenAgentOwner721.sol";


contract EigenAgent6551 is ERC6551 {

    /// @notice The EIP-712 typehash for the deposit struct used by the contract
    bytes32 public constant EIGEN_AGENT_EXEC_TYPEHASH = keccak256(
        "ExecuteWithSignature(address target,uint256 value,bytes data,uint256 execNonce,uint256 chainId,uint256 expiry)"
    );

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice Nonce for signing executeWithSignature calls
    uint256 public execNonce;

    event ExecutedSignedCall(
        address indexed targetContract,
        bool indexed success,
        bytes indexed result
    );
    event SignatureInvalidEvent(bytes32 indexed digestHash, bytes signature);

    error CallerNotWhitelisted(string reason);
    error SignatureInvalid(string reason);

    modifier onlyWhitelistedCallers() {
        // get the 721 NFT associated with 6551 account and check if caller is whitelisted
        (uint256 chainId, address contractAddress, uint256 tokenId) = token();
        if (!IEigenAgentOwner721(contractAddress).isWhitelistedCaller(msg.sender)) {
            revert CallerNotWhitelisted("EigenAgent: caller not allowed");
        }
        _;
    }

    /**
     * @dev This function is used by RestakingConnector.sol to approve Eigenlayer StrategyManager
     * to transfer and EigenAgent's tokens into Eigenlayer strategy vaults. This avoids needing
     * to extra transfers and signed messages to complete L2 restaking deposits.
     * @param targetContract to approve transfer for, expected to be the Eigenlayer StrategyManager contract
     * @param token the token used in the Eigenlayer Strategy vault.
     * @param amount of tokens user is depositing into the strategy vault.
     */
    function approveByWhitelistedContract(
        address targetContract,
        address token,
        uint256 amount
    ) external onlyWhitelistedCallers returns (bool) {
        return IERC20(token).approve(targetContract, amount);
    }

    /**
     * @dev EigenAgent receives messages (data) and executes commands on behalf of it's owner
     * on L2. The EigenAgent will only execute if provided a valid signature from the owner of the
     * EigenAgentOwner721 NFT associated with the ERC-6551 EigenAgent account.
     * @param targetContract is the contract to call
     * @param value amount of ETH to send with the call
     * @param data the data (message) to send to targetContract (e.g. depositIntoStrategy calldata)
     * @param expiry expiry of the signature, currently only used to give users an option to withdraw
     * bridged funds (for a deposit) if the call reverts after a period of a time (e.g in case an
     * Operator deactivates in the time it takes to bridge from L2 to L1 and deposit).
     * @param signature is the owner of the EigenAgent's signature, signed over the hash of the
     * data that the EigenAgent calls the targetContract with.
     */
    function executeWithSignature(
        address targetContract,
        uint256 value,
        bytes calldata data,
        uint256 expiry,
        bytes memory signature
    )
        external
        payable
        virtual
        returns (bytes memory result)
    {

        // require(expiry >= block.timestamp, "Signature for EigenAgent execution expired");
        /// Note: do not revert on expiry. CCIP may take hours to deliver messages if gas spikes.
        /// We would need to return funds to the user on L2, as the transaction may no longer be
        /// manually executable after gas lowers later (e.g. Operator goes offline).

        bytes32 digestHash = createEigenAgentCallDigestHash(
            targetContract,
            value,
            data,
            execNonce,
            block.chainid,
            expiry
        );

        if (isValidSignature(digestHash, signature) != IERC1271.isValidSignature.selector) {
            emit SignatureInvalidEvent(digestHash, signature);
            revert SignatureInvalid("Invalid signer, or incorrect digestHash parameters.");
        }

        ++execNonce;
        bool success;

        (success, result) = targetContract.call{value: value}(data);

        emit ExecutedSignedCall(targetContract, success, result);

        // Forward error strings up the callstack
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }

        return result;
    }

    /**
     * @dev Checks if signature is valid according to ERC-1271. If the signer is an EOA,
     * it validates signatures using ecrecover. If the signer is a contract, calls isValidSignature
     * on the contract to determin if the signatuer is valid. For an example, see MockMultisigSigner.sol
     * contract and associated tests.
     */
    function isValidSignature(
        bytes32 digestHash,
        bytes memory signature
    ) public view virtual override returns (bytes4) {
        address signer = owner();
        if (SignatureChecker.isValidSignatureNow(signer, digestHash, signature)) {
            return IERC1271.isValidSignature.selector;
        } else {
            return bytes4(0);
        }
    }

    /**
     * @dev Creates a digestHash of the Eigenlayer command (e.g depositIntoStrategy) to be sent through CCIP.
     * @param target contract for the EigenAgent to call
     * @param value amount of Eth to send with the call
     * @param data to send (e.g. encoded queueWithdrawal parameters) to target contract (DelegationManager)
     * @param nonce execution nonce used in EigenAgent execution signatures
     * @param chainid is the chain EigenAgent and Eigenlayer is deployed on.
     * @param expiry expiry parameter for signature (currently does not revert if expired)
     */
    function createEigenAgentCallDigestHash(
        address target,
        uint256 value,
        bytes calldata data,
        uint256 nonce,
        uint256 chainid,
        uint256 expiry
    ) public pure returns (bytes32) {
        // EIP-712 struct hash
        bytes32 structHash = keccak256(abi.encode(
            EIGEN_AGENT_EXEC_TYPEHASH,
            target,
            value,
            data,
            nonce,
            chainid,
            expiry
        ));
        // calculate the digest hash
        bytes32 digestHash = keccak256(abi.encodePacked(
            "\x19\x01",
            domainSeparator(target, chainid),
            structHash
        ));

        return digestHash;
    }

    /**
     * @param contractAddr is the address of the contract where the signature will be verified,
     * either EigenAgent, Eigenlayer StrategyManager, or DelegationManager.
     * @param chainid is the chain Eigenlayer and EigenAgent are deployed on.
     */
    function domainSeparator(
        address contractAddr, // strategyManagerAddr, or delegationManagerAddr
        uint256 chainid
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes("EigenLayer")), chainid, contractAddr));
    }
}

