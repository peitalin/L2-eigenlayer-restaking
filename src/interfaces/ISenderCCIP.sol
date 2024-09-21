// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IBaseMessengerCCIP} from "./IBaseMessengerCCIP.sol";
import {ISenderHooks} from "./ISenderHooks.sol";

interface ISenderCCIP is IBaseMessengerCCIP {

    function getSenderHooks() external returns (ISenderHooks);

    function setSenderHooks(ISenderHooks _senderHooks) external;
}

