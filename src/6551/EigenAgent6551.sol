// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ERC6551Account} from "./ERC6551Account.sol";
import {IEigenAgent6551} from "./IEigenAgent6551.sol";
import {IEigenAgentOwner721} from "./IEigenAgentOwner721.sol";

import {console} from "forge-std/Test.sol";


contract EigenAgent6551 is ERC6551Account, IEigenAgent6551 {

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

    function getAgentOwner() public view returns (address) {
        return owner();
    }

    function isValidSignature(
        bytes32 digestHash,
        bytes memory signature
    ) public view virtual override returns (bytes4) {
        bool isValid = ECDSA.recover(digestHash, signature) == owner(); // owner of the NFT
        if (isValid) {
            return IERC1271.isValidSignature.selector;
        }

        return bytes4(0);
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
            getDomainSeparator(target, chainid),
            structHash
        ));

        return digestHash;
    }

    /// @param contractAddr is the address of the contract being called,
    /// usually Eigenlayer StrategyManager, or DelegationManager.
    /// @param chainid is the chain Eigenlayer is deployed on
    function getDomainSeparator(
        address contractAddr, // strategyManagerAddr, or delegationManagerAddr
        uint256 chainid
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes("EigenLayer")), chainid, contractAddr));
    }
}
