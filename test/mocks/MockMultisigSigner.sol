//SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/interfaces/IERC721Receiver.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Adminable} from "../../src/utils/Adminable.sol";


contract MockMultisigSigner is Adminable, IERC721Receiver {

    uint256 SIGNATURES_REQUIRED = 2;

    event NumberOfSignatures(bytes32 digestHash, uint256 numSigned);

    mapping(bytes32 digestHash => address[]) digestHashSigners;

    error AlreadySigned();

    constructor() {
        Adminable.__Adminable_init();
    }

    function signHash(
        bytes32 digestHash,
        bytes memory signature
    ) public {

        address signer = ECDSA.recover(digestHash, signature);

        if (isAdmin(signer)) {
            // see if already signed
            address[] memory signers = digestHashSigners[digestHash];
            uint256 numSigned = signers.length;

            for (uint256 i = 0; i < numSigned; ++i) {
                if (signers[i] == signer) {
                    revert AlreadySigned();
                }
            }

            digestHashSigners[digestHash].push(signer);

            emit NumberOfSignatures(digestHash, numSigned + 1);
        }
    }

    function isValidSignature(
        bytes32 digestHash,
        bytes memory signature
    ) public view returns (bytes4 magicValue) {

        address[] memory signers = digestHashSigners[digestHash];

        if (signers.length == SIGNATURES_REQUIRED) {
            return IERC1271.isValidSignature.selector;
        }
        return bytes4(0);
    }

    function onERC721Received(
        address, // operator
        address, // from
        uint256, // tokenId
        bytes calldata // data
    ) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    receive() external payable {}
}