//SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HashAgentOwnerRoot} from "./HashAgentOwnerRoot.sol";


library DelegationDecoders {

    /*
     *
     *
     *                   DelegateTo
     *
     *
    */

    // function decodeDelegateToMsg(bytes memory message)
    //     public pure
    //     returns (
    //         address,
    //         ISignatureUtils.SignatureWithExpiry memory,
    //         bytes32
    //     )
    // {
    //     // function delegateTo(
    //     //     address operator,
    //     //     SignatureWithExpiry memory approverSignatureAndExpiry,
    //     //     bytes32 approverSalt
    //     // )

    //     uint256 msg_length;
    //     uint256 staker_sig_offset;
    //     uint256 approver_sig_offset;
    //     assembly {
    //         msg_length := mload(add(message, 64))
    //         staker_sig_offset := mload(add(message, 164))
    //         approver_sig_offset := mload(add(message, 196))
    //     }

    //     return (
    //         staker,
    //         operator,
    //         stakerSignatureAndExpiry,
    //         approverSignatureAndExpiry,
    //         approverSalt
    //     );
    // }

    function decodeDelegateToBySignatureMsg(bytes memory message)
        public pure
        returns (
            address,
            address,
            ISignatureUtils.SignatureWithExpiry memory,
            ISignatureUtils.SignatureWithExpiry memory,
            bytes32
        )
    {
        // function delegateToBySignature(
        //     address staker,
        //     address operator,
        //     SignatureWithExpiry memory stakerSignatureAndExpiry,
        //     SignatureWithExpiry memory approverSignatureAndExpiry,
        //     bytes32 approverSalt
        // )

        ////// 2x ECDSA signatures, 65 length each
        // 0000000000000000000000000000000000000000000000000000000000000020 [32] string offset
        // 0000000000000000000000000000000000000000000000000000000000000224 [64] string length
        // 7f548071                                                         [96] function selector
        // 0000000000000000000000007e5f4552091a69125d5dfcb7b8c2659029395bdf [100] staker
        // 0000000000000000000000002b5ad5c4795c026514f8317c7a215e218dccd6cf [132] operator
        // 00000000000000000000000000000000000000000000000000000000000000a0 [164] staker_sig_struct offset [5 lines]
        // 0000000000000000000000000000000000000000000000000000000000000160 [196] approver_sig_struct offset [11 lines]
        // 0000000000000000000000000000000000000000000000000000000000004444 [228] approver salt
        // 0000000000000000000000000000000000000000000000000000000000000040 [260] staker_sig offset
        // 0000000000000000000000000000000000000000000000000000000000000005 [292] staker_sig expiry
        // 0000000000000000000000000000000000000000000000000000000000000041 [324] staker_sig length (hex 0x41 = 65 bytes)
        // bfb59bee8b02985b56e9c5b7cea3a900d54440b7ef0e3b41a56e6613a8bb7ead [356] staker_sig r
        // 4e082b1bb02486715bfb87b4a7202becd6df26dd4a6addb214e6748188d5e02e [388] staker_sig s
        // 1c00000000000000000000000000000000000000000000000000000000000000 [420] staker_sig v
        // 0000000000000000000000000000000000000000000000000000000000000040 [452] approver_sig offset
        // 0000000000000000000000000000000000000000000000000000000000000006 [484] approver_sig expiry
        // 0000000000000000000000000000000000000000000000000000000000000041 [516] approver_sig length (hex 41 = 65 bytes)
        // 71d0163eec33ce78295b1b94a3a43a2ea4db2219973c68ab02f16a2d88b94ce5 [548] approver_sig r
        // 3c3336c813404285f90c817c830a47facefa2a826dd33f69e14c076fbdf444b7 [580] approver_sig s
        // 1c00000000000000000000000000000000000000000000000000000000000000 [612] approver_sig v
        // 00000000000000000000000000000000000000000000000000000000

        uint256 msg_length;
        uint256 staker_sig_offset;
        uint256 approver_sig_offset;
        assembly {
            msg_length := mload(add(message, 64))
            staker_sig_offset := mload(add(message, 164))
            approver_sig_offset := mload(add(message, 196))
        }

        address staker;
        address operator;
        bytes32 approverSalt;
        ISignatureUtils.SignatureWithExpiry memory stakerSignatureAndExpiry;
        ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry;

        assembly {
            staker := mload(add(message, 100))
            operator := mload(add(message, 132))
            approverSalt := mload(add(message, 228))
        }

        if (msg_length == 356) {
            // staker_sig: 0
            // approver_sig: 0
            stakerSignatureAndExpiry = _getDelegationNullSignature(message, 0);
            approverSignatureAndExpiry = _getDelegationNullSignature(message, 96);

        } else if (msg_length == 452 && approver_sig_offset == 352) {
            // staker_sig: 1
            // approver_sig: 0

            // 0000000000000000000000000000000000000000000000000000000000000020
            // 00000000000000000000000000000000000000000000000000000000000001c4
            // 7f548071
            // 0000000000000000000000007e5f4552091a69125d5dfcb7b8c2659029395bdf
            // 0000000000000000000000002b5ad5c4795c026514f8317c7a215e218dccd6cf
            // 00000000000000000000000000000000000000000000000000000000000000a0 [164] staker_sig_struct offset [5 lines]
            // 0000000000000000000000000000000000000000000000000000000000000160 [196] approver_sig_struct offset [11 lines]
            // 0000000000000000000000000000000000000000000000000000000000004444 [228]
            // 0000000000000000000000000000000000000000000000000000000000000040 [260] staker_sig offset
            // 0000000000000000000000000000000000000000000000000000000000000005 [292]
            // 0000000000000000000000000000000000000000000000000000000000000041 [324] staker_sig length
            // bfb59bee8b02985b56e9c5b7cea3a900d54440b7ef0e3b41a56e6613a8bb7ead
            // 4e082b1bb02486715bfb87b4a7202becd6df26dd4a6addb214e6748188d5e02e
            // 1c00000000000000000000000000000000000000000000000000000000000000
            // 0000000000000000000000000000000000000000000000000000000000000040 [452] approver_sig offset
            // 0000000000000000000000000000000000000000000000000000000000000006
            // 0000000000000000000000000000000000000000000000000000000000000000
            // 00000000000000000000000000000000000000000000000000000000

            stakerSignatureAndExpiry = _getDelegationSignature(message, 0);
            approverSignatureAndExpiry = _getDelegationNullSignature(message, 192); // 96 offset more

        } else if (msg_length == 452 && approver_sig_offset == 256) {
            // staker_sig: 0
            // approver_sig: 1
            stakerSignatureAndExpiry = _getDelegationNullSignature(message, 0);
            approverSignatureAndExpiry = _getDelegationSignature(message, 96);

        } else if (msg_length == 548) {
            // staker_sig: 1
            // approver_sig: 1
            stakerSignatureAndExpiry = _getDelegationSignature(message, 0);
            // 192 offset for approver signature
            approverSignatureAndExpiry = _getDelegationSignature(message, 192);
        }

        return (
            staker,
            operator,
            stakerSignatureAndExpiry,
            approverSignatureAndExpiry,
            approverSalt
        );
    }


    function _getDelegationSignature(bytes memory message, uint256 offset)
        internal pure
        returns (ISignatureUtils.SignatureWithExpiry memory)
    {

        uint256 expiry;
        bytes memory signature;
        bytes32 r;
        bytes32 s;
        bytes1 v;

        assembly {
            expiry := mload(add(message, add(292, offset)))
            r := mload(add(message, add(356, offset)))
            s := mload(add(message, add(388, offset)))
            v := mload(add(message, add(420, offset)))
        }

        signature = abi.encodePacked(r, s, v);

        ISignatureUtils.SignatureWithExpiry memory signatureAndExpiry = ISignatureUtils.SignatureWithExpiry({
            signature: signature,
            expiry: expiry
        });

        return signatureAndExpiry;
    }


    function _getDelegationNullSignature(bytes memory message, uint256 offset)
        internal pure
        returns (ISignatureUtils.SignatureWithExpiry memory)
    {

        ///// Null signatures:
        // 0000000000000000000000000000000000000000000000000000000000000020 [32]
        // 0000000000000000000000000000000000000000000000000000000000000164 [64]
        // 7f548071                                                         [96]
        // 0000000000000000000000007e5f4552091a69125d5dfcb7b8c2659029395bdf [100] staker
        // 0000000000000000000000002b5ad5c4795c026514f8317c7a215e218dccd6cf [132] operator
        // 00000000000000000000000000000000000000000000000000000000000000a0 [164] staker_sig_struct offset [5 lines]
        // 0000000000000000000000000000000000000000000000000000000000000100 [196] approver_sig_struct offset [8 lines]
        // 0000000000000000000000000000000000000000000000000000000000004444 [228] approverSalt
        // 0000000000000000000000000000000000000000000000000000000000000040 [260] staker_sig offset (bytes has a offset and length)
        // 0000000000000000000000000000000000000000000000000000000000000005 [292] staker_sig expiry
        // 0000000000000000000000000000000000000000000000000000000000000000 [324] staker_signature
        // 0000000000000000000000000000000000000000000000000000000000000040 [356] approver_sig offset
        // 0000000000000000000000000000000000000000000000000000000000000006 [388] approver_sig expiry
        // 0000000000000000000000000000000000000000000000000000000000000000 [420] approver_signature
        // 00000000000000000000000000000000000000000000000000000000

        uint256 expiry;
        bytes memory signature;

        assembly {
            expiry := mload(add(message, add(292, offset)))
            signature := mload(add(message, add(324, offset)))
        }

        ISignatureUtils.SignatureWithExpiry memory signatureAndExpiry = ISignatureUtils.SignatureWithExpiry({
            signature: signature,
            expiry: expiry
        });

        return signatureAndExpiry;
    }


    function decodeUndelegateMsg(bytes memory message)
        public pure
        returns (address)
    {
        // 0000000000000000000000000000000000000000000000000000000000000020 [32]
        // 0000000000000000000000000000000000000000000000000000000000000224 [64]
        // 54b2bf29                                                         [96]
        // 00000000000000000000000071c6f7ed8c2d4925d0baf16f6a85bb1736d412eb [100] address
        // 00000000000000000000000000000000000000000000000000000000

        bytes4 functionSelector;
        address staker;

        assembly {
            functionSelector := mload(add(message, 96))
            staker := mload(add(message, 100))
        }

        return staker;
    }
}
