// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IRestakingConnector} from "./IRestakingConnector.sol";
import {IBaseMessengerCCIP} from "./IBaseMessengerCCIP.sol";


interface IReceiverCCIP is IBaseMessengerCCIP {

    function getSenderContractL2() external view returns (address);

    function setSenderContractL2(address _senderContract) external;

    function getRestakingConnector() external view returns (IRestakingConnector);

    function setRestakingConnector(IRestakingConnector _restakingConnector) external;

    function amountRefunded(bytes32 messageId, address token) external view returns (uint256);

    function withdrawTokenForMessageId(
        bytes32 messageId,
        address beneficiary,
        address token,
        uint256 amount
    ) external;
}

