// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Base6551Account} from "./Base6551Account.sol";
import {IEigenAgentOwner721} from "./IEigenAgentOwner721.sol";
import {SignatureCheckerV5} from "../utils/SignatureCheckerV5.sol";


contract EigenAgent6551 is Base6551Account {

    /// @notice The EIP-712 typehash for the deposit struct used by the contract
    bytes32 public constant EIGEN_AGENT_EXEC_TYPEHASH = keccak256(
        "ExecuteWithSignature(address target,uint256 value,bytes data,uint256 execNonce,uint256 chainId,uint256 expiry)"
    );

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    error CallerNotWhitelisted();
    error SignatureNotFromNftOwner();

    modifier onlyWhitelistedCallers() {
        // get the 721 NFT associated with 6551 account and check if caller is whitelisted
        (uint256 chainId, address contractAddress, uint256 tokenId) = token();
        if (!IEigenAgentOwner721(contractAddress).isWhitelistedCaller(msg.sender)) {
            revert CallerNotWhitelisted();
        }
        _;
    }

    function isValidSignature(
        bytes32 digestHash,
        bytes memory signature
    ) public view virtual override returns (bytes4) {
        address signer = owner();
        if (SignatureCheckerV5.isValidSignatureNow(signer, digestHash, signature)) {
            return IERC1271.isValidSignature.selector;
        } else {
            return bytes4(0);
        }
    }

    function approveByWhitelistedContract(
        address targetContract,
        address token,
        uint256 amount
    ) external onlyWhitelistedCallers returns (bool) {
        return IERC20(token).approve(targetContract, amount);
    }

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
        /// Do revert on expiry.
        /// CCIP may take hours to deliver messages when gas spikes.
        /// We would need to return funds to the user on L2 this case,
        /// as the transaction may no longer be manually executable after gas lowers later.
        ///
        // require(expiry >= block.timestamp, "Signature for EigenAgent execution expired");

        bytes32 digestHash = createEigenAgentCallDigestHash(
            targetContract,
            value,
            data,
            execNonce,
            block.chainid,
            expiry
        );

        if (isValidSignature(digestHash, signature) != IERC1271.isValidSignature.selector)
            revert SignatureNotFromNftOwner();

        ++execNonce;
        bool success;

        {
            // solhint-disable-next-line avoid-low-level-calls
            (success, result) = targetContract.call{value: value}(data);
        }

        require(success, string(result));
        return result;
    }

    function createEigenAgentCallDigestHash(
        address target,
        uint256 value,
        bytes calldata data,
        uint256 nonce,
        uint256 chainid,
        uint256 expiry
    ) public pure returns (bytes32) {

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

    /// @param contractAddr is the address of the contract being called,
    /// usually Eigenlayer StrategyManager, or DelegationManager.
    /// @param chainid is the chain Eigenlayer is deployed on
    function domainSeparator(
        address contractAddr, // strategyManagerAddr, or delegationManagerAddr
        uint256 chainid
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes("EigenLayer")), chainid, contractAddr));
    }
}

