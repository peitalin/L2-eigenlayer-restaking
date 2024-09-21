// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IRestakingConnector} from "./IRestakingConnector.sol";
import {IBaseMessengerCCIP} from "./IBaseMessengerCCIP.sol";


interface IReceiverCCIP is IBaseMessengerCCIP {

    function getSenderContractL2Addr() external view returns (address);

    function setSenderContractL2Addr(address _senderContract) external;

    function getRestakingConnector() external view returns (IRestakingConnector);

    function setRestakingConnector(IRestakingConnector _restakingConnector) external;

    function amountRefunded(bytes32 messageId) external view returns (uint256);

    function setAmountRefundedToMessageId(bytes32 messageId, uint256 amountAfter) external;
}

