// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC1271} from "@openzeppelin-v5-contracts/interfaces/IERC1271.sol";
import {IERC20} from "@openzeppelin-v5-contracts/token/ERC20/IERC20.sol";
import {SignatureChecker} from "@openzeppelin-v5-contracts/utils/cryptography/SignatureChecker.sol";
import {SafeERC20} from "@openzeppelin-v5-contracts/token/ERC20/utils/SafeERC20.sol";

import {ERC6551Account as ERC6551} from "@6551/examples/simple/ERC6551Account.sol";
import {IEigenAgentOwner721} from "./IEigenAgentOwner721.sol";


contract EigenAgent6551 is ERC6551 {

    using SafeERC20 for IERC20;

    /// @notice The EIP-712 typehash for the deposit struct used by the contract
    bytes32 public constant EIGEN_AGENT_EXEC_TYPEHASH = keccak256(
        "ExecuteWithSignature(address target,uint256 value,bytes data,uint256 execNonce,uint256 chainId,uint256 expiry)"
    );

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    /// @notice Eigenlayer Version
    string public constant EIGENLAYER_VERSION = "v1.3.0";

    /// @notice Nonce for signing executeWithSignature calls
    uint256 public execNonce;

    /// @notice Only the RestakingConnector address can call executeWithSignature
    address public restakingConnector;

    event ExecutedSignedCall(
        address indexed targetContract,
        bool indexed success,
        bytes indexed result
    );
    event SignatureInvalidEvent(bytes32 indexed digestHash, bytes signature);

    error CallerNotWhitelisted(string reason);
    error SignatureInvalid(string reason);
    error RestakingConnectorAlreadyInitialized();
    error AddressZero(string reason);

    modifier onlyWhitelistedCallers() {
        // get the 721 NFT associated with 6551 account and check if caller is whitelisted
        (uint256 chainId, address contractAddress, uint256 tokenId) = token();
        if (!IEigenAgentOwner721(contractAddress).isWhitelistedCaller(msg.sender)) {
            revert CallerNotWhitelisted("EigenAgent6551: caller not allowed");
        }
        _;
    }

    /**
     * @dev Initializes the EigenAgent6551 with a RestakingConnector address
     * @param _restakingConnector The address of the RestakingConnector contract
     */
    function setInitialRestakingConnector(address _restakingConnector) external {
        // Only allow initialization if restakingConnector is not set yet
        if (restakingConnector != address(0)) revert RestakingConnectorAlreadyInitialized();
        if (_restakingConnector == address(0)) revert AddressZero("EigenAgent6551: invalid RestakingConnector");
        restakingConnector = _restakingConnector;
    }

    /**
     * @dev This function is used by RestakingConnector.sol to approve Eigenlayer StrategyManager
     * to transfer and EigenAgent's tokens into Eigenlayer strategy vaults. This avoids needing
     * extra transfers and signed messages to complete L2 restaking deposits.
     * @param spenderContract to approve transfer for, expected to be the Eigenlayer StrategyManager contract
     * @param token the token used in the Eigenlayer Strategy vault.
     * @param amount of tokens user is depositing into the strategy vault.
     */
    function approveByWhitelistedContract(
        address spenderContract,
        address token,
        uint256 amount
    ) external onlyWhitelistedCallers {
        // forceApprove handles the two-step approval process internally
        // for tokens like USDT that require setting to 0 first
        IERC20(token).forceApprove(spenderContract, amount);
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
        // Only allow RestakingConnector or NFT owner to call this function
        require(
            msg.sender == restakingConnector || msg.sender == owner(),
            "Only RestakingConnector or owner can execute"
        );

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
    ) public view returns (bytes32) {
        // EIP-712 struct hash
        bytes32 structHash = keccak256(abi.encode(
            EIGEN_AGENT_EXEC_TYPEHASH,
            target,
            value,
            keccak256(data),
            nonce,
            chainid,
            expiry
        ));
        // calculate the digest hash
        bytes32 digestHash = keccak256(abi.encodePacked(
            "\x19\x01",
            domainSeparator(chainid),
            structHash
        ));

        return digestHash;
    }

    /**
     * @param chainid is the chain Eigenlayer and EigenAgent are deployed on.
     * @dev domainSeparator defined in eigenlayer-contracts/src/contracts/mixins/SignatureUtilsMixin.sol
     */
    function domainSeparator(
        uint256 chainid
    ) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("EigenLayer")),
                keccak256(bytes(_majorVersion())),
                chainid,
                address(this)
            )
        );
    }


    /// @notice Returns the major version of the contract. See Eigenlayer SemVerMixin.sol
    /// @return The major version string (e.g., "v1" for version "v1.2.3")
    function _majorVersion() internal pure returns (string memory) {
        bytes memory v = bytes(EIGENLAYER_VERSION);
        return string(bytes.concat(v[0], v[1]));
    }
}

