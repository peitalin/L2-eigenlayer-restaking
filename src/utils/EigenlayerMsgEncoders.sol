//SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

contract EigenlayerMsgEncoders {

    function encodeDepositIntoStrategyWithSignatureMsg(
        address strategy,
        address token,
        uint256 amount,
        address staker,
        uint256 expiry,
        bytes memory signature
    ) public pure returns (bytes memory) {

        // encode message payload
        bytes memory message_bytes = abi.encodeWithSelector(
            bytes4(keccak256("depositIntoStrategyWithSignature(address,address,uint256,address,uint256,bytes)")),
            strategy,
            token,
            amount,
            staker,
            expiry,
            signature
        );
        // CCIP turns the message into string when sending
        // bytes memory message = abi.encode(string(message_bytes));
        return message_bytes;
    }
}
