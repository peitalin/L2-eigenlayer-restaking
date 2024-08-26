// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {ISenderCCIP} from "./ISenderCCIP.sol";
import {ISenderUtils} from "./ISenderUtils.sol";
import {IRestakingConnector} from "./IRestakingConnector.sol";
import {IBaseMessengerCCIP} from "./IBaseMessengerCCIP.sol";
import {EigenAgent6551} from "../6551/EigenAgent6551.sol";
import {EigenAgentOwner721} from "../6551/EigenAgentOwner721.sol";
import {IERC6551Registry} from "@6551/interfaces/IERC6551Registry.sol";



interface IReceiverCCIP is IBaseMessengerCCIP {

    function mockCCIPReceive(Client.Any2EVMMessage memory any2EvmMessage) external;

    function setSenderutils(ISenderUtils _senderUtils) external;

    function getSenderContractL2Addr() external view returns (address);

    function setSenderContractL2Addr(address _senderContractAddr) external;

    function getRestakingConnector() external view returns (IRestakingConnector);

    function setRestakingConnector(IRestakingConnector _restakingConnector) external;

}

