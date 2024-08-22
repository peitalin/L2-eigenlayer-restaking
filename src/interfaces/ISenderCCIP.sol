// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IBaseMessengerCCIP} from "./IBaseMessengerCCIP.sol";
import {ISenderUtils} from "./ISenderUtils.sol";
import {SenderCCIP} from "../SenderCCIP.sol";

interface ISenderCCIP is IBaseMessengerCCIP {

    function mockCCIPReceive(Client.Any2EVMMessage memory any2EvmMessage) external;

    function setSenderUtils(ISenderUtils _senderUtils) external;

    function getWithdrawal(bytes32 withdrawalRoot) external returns (SenderCCIP.WithdrawalTransfer memory);
}

