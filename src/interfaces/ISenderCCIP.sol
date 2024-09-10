// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IBaseMessengerCCIP} from "./IBaseMessengerCCIP.sol";
import {ISenderHooks} from "./ISenderHooks.sol";

interface ISenderCCIP is IBaseMessengerCCIP {

    function getSenderHooks() external returns (ISenderHooks);

    function setSenderHooks(ISenderHooks _senderHooks) external;
}

