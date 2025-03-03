// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Client} from "@chainlink/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/ccip/interfaces/IRouterClient.sol";
import {EthHolesky, BaseSepolia} from "./Addresses.sol";


contract RouterFees {

    function getRouterFeesL1(
        address _receiver,
        string memory _message,
        Client.EVMTokenAmount[] memory _tokenAmounts,
        uint256 _gasLimit
    ) public view returns (uint256) {

        return IRouterClient(EthHolesky.Router).getFee(
            BaseSepolia.ChainSelector,
            Client.EVM2AnyMessage({
                receiver: abi.encode(_receiver),
                data: abi.encode(_message),
                tokenAmounts: _tokenAmounts,
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
        Client.EVMTokenAmount[] memory _tokenAmounts,
        uint256 _gasLimit
    ) public view returns (uint256) {

        return IRouterClient(BaseSepolia.Router).getFee(
            EthHolesky.ChainSelector,
            Client.EVM2AnyMessage({
                receiver: abi.encode(_receiver),
                data: abi.encode(_message),
                tokenAmounts: _tokenAmounts,
                feeToken: address(0), // native gas
                extraArgs: Client._argsToBytes(
                    Client.EVMExtraArgsV1({ gasLimit: _gasLimit })
                )
            })
        );
    }
}
