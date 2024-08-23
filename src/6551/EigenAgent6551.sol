// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

// import {ERC6551AccountUpgradeable} from "@6551/examples/upgradeable/ERC6551AccountUpgradeable.sol";
import {ERC6551AccountUpgradeable} from "./ERC6551AccountUpgradeable.sol";
import {IERC6551Account} from "@6551/interfaces/IERC6551Account.sol";
import {IERC6551Executable} from "@6551/interfaces/IERC6551Executable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IEigenAgent6551} from "./IEigenAgent6551.sol";
import {SignatureUtilsEIP1271} from "../utils/SignatureUtilsEIP1271.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {console} from "forge-std/Test.sol";


contract EigenAgent6551 is ERC6551AccountUpgradeable, IEigenAgent6551 {

    /*
     *
     *            Constants
     *
     */

    uint256 public execNonce;

    /// @notice The EIP-712 typehash for the deposit struct used by the contract
    bytes32 public constant EIGEN_AGENT_EXEC_TYPEHASH = keccak256("ExecuteWithSignature(address target, uint256 value, bytes data, uint256 expiry)");

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    error CallerIsNotOwner();
    error SignatureNotFromNftOwner();
    error OnlyCallOperationsSupported();

    /*
     *
     *            Functions
     *
     */

    function beforeExecute(bytes calldata data) public override virtual returns (bytes4) {
        return IEigenAgent6551.beforeExecute.selector;
    }

    function afterExecute(
        bytes calldata data,
        bool success,
        bytes memory result
    ) public override virtual returns (bytes4) {
        return IEigenAgent6551.afterExecute.selector;
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

    modifier onlySignedByNftOwner(
        bytes32 _digestHash,
        bytes memory _signature
    ) {
        if (isValidSignature(_digestHash, _signature) != IERC1271.isValidSignature.selector)
            revert SignatureNotFromNftOwner();
        _;
    }

    function executeWithSignature(
        address _target,
        uint256 _value,
        bytes calldata _data,
        uint256 _expiry,
        bytes memory _signature
    )
        external
        payable
        virtual
        returns (bytes memory _result)
    {
        // no longer need msg.sender == nftOwner constraint
        // if (!_isValidSigner(msg.sender)) revert CallerIsNotOwner();
        bytes32 _digestHash = createEigenAgentCallDigest(
            _target,
            _value,
            _data,
            execNonce,
            block.chainid,
            _expiry
        );

        if (isValidSignature(_digestHash, _signature) != IERC1271.isValidSignature.selector)
            revert SignatureNotFromNftOwner();

        ++state;
        bool success;

        beforeExecute(_data);
        {
            // solhint-disable-next-line avoid-low-level-calls
            (success, _result) = _target.call{value: _value}(_data);
        }
        afterExecute(_data, success, _result);

        require(success, string(_result));
        return _result;
    }

    function createEigenAgentCallDigest(
        address _target,
        uint256 _value,
        bytes calldata _data,
        uint256 _nonce,
        uint256 _chainid,
        uint256 _expiry
    ) public view returns (bytes32) {

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

    function getDomainSeparator(
        address contractAddr, // strategyManagerAddr, or delegationManagerAddr
        uint256 destinationChainid
    ) public view returns (bytes32) {

        uint256 chainid = destinationChainid;

        return keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes("EigenLayer")), chainid, contractAddr));
        // Note: in calculating the domainSeparator:
        // address(this) is the StrategyManager, not this contract (SignatureUtilsEIP2172)
        // chainid is the chain Eigenlayer is deployed on (it can fork!), not the chain you are calling this function
        // So chainid should be destination chainid in the context of L2 -> L1 restaking calls
    }

}