// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Client} from "@chainlink/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/ccip/interfaces/IRouterClient.sol";
import {EthSepolia, BaseSepolia} from "./Addresses.sol";


contract RouterFees {

    function getRouterFeesL1(
        address _receiver,
        string memory _message,
        address _tokenL1,
        uint256 _amount,
        uint256 _gasLimit
    ) public view returns (uint256) {

        Client.EVMTokenAmount[] memory tokenAmounts;

        if (_amount <= 0) {
            // Must be an empty array as no tokens are transferred
            // non-empty arrays with 0 amounts error with CannotSendZeroTokens() == 0x5cf04449
            tokenAmounts = new Client.EVMTokenAmount[](0);
        } else {
            tokenAmounts = new Client.EVMTokenAmount[](1);
            tokenAmounts[0] = Client.EVMTokenAmount({
                token: _tokenL1,
                amount: _amount
            });
        }

        return IRouterClient(EthSepolia.Router).getFee(
            BaseSepolia.ChainSelector,
            Client.EVM2AnyMessage({
                receiver: abi.encode(_receiver),
                data: abi.encode(_message),
                tokenAmounts: tokenAmounts,
                feeToken: address(0), // native gas
                extraArgs: Client._argsToBytes(
                    Client.EVMExtraArgsV1({ gasLimit: _gasLimit })
                )
            })
        );
    }

    function getRouterFeesL2(
        address _receiver,
        string memory _message,
        address _tokenL2,
        uint256 _amount,
        uint256 _gasLimit
    ) public view returns (uint256) {

        Client.EVMTokenAmount[] memory tokenAmounts;

        if (_amount <= 0) {
            // Must be an empty array as no tokens are transferred
            // non-empty arrays with 0 amounts error with CannotSendZeroTokens() == 0x5cf04449
            tokenAmounts = new Client.EVMTokenAmount[](0);
        } else {
            tokenAmounts = new Client.EVMTokenAmount[](1);
            tokenAmounts[0] = Client.EVMTokenAmount({
                token: _tokenL2,
                amount: _amount
            });
        }

        return IRouterClient(BaseSepolia.Router).getFee(
            EthSepolia.ChainSelector,
            Client.EVM2AnyMessage({
                receiver: abi.encode(_receiver),
                data: abi.encode(_message),
                tokenAmounts: tokenAmounts,
                feeToken: address(0), // native gas
                extraArgs: Client._argsToBytes(
                    Client.EVMExtraArgsV1({ gasLimit: _gasLimit })
                )
            })
        );
    }
}
