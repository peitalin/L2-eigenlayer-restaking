// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {FunctionSelectorDecoder} from "./FunctionSelectorDecoder.sol";
import {EigenlayerMsgDecoders} from "./utils/EigenlayerMsgDecoders.sol";


contract SenderUtils is EigenlayerMsgDecoders, Ownable {

    event SetGasLimitForFunctionSelector(bytes4 indexed, uint256 indexed);

    mapping(bytes4 => uint256) internal gasLimitsForFunctionSelectors;

    mapping(bytes4 => string) internal functionSelectorNames;

    constructor() {

        // depositIntoStrategy: [gas: 565_307]
        gasLimitsForFunctionSelectors[0xf7e784ef] = 600_000;
        functionSelectorNames[0xf7e784ef] = "depositIntoStrategy";

        // depositIntoStrategyWithSignature: [gas: 713_400]
        gasLimitsForFunctionSelectors[0x32e89ace] = 800_000;
        functionSelectorNames[0x32e89ace] = "depositIntoStrategyWithSignature";

        // queueWithdrawals: [gas: x]
        gasLimitsForFunctionSelectors[0x0dd8dd02] = 700_000;
        functionSelectorNames[0x0dd8dd02] = "queueWithdrawals";

        // queueWithdrawalsWithSignature: [gas: 603_301]
        gasLimitsForFunctionSelectors[0xa140f06e] = 800_000;
        functionSelectorNames[0xa140f06e] = "queueWithdrawalsWithSignature";

        // completeQueuedWithdrawals: [gas: 645_948]
        gasLimitsForFunctionSelectors[0x54b2bf29] = 800_000;
        functionSelectorNames[0x54b2bf29] = "completeQueuedWithdrawals";

        // delegateToBySignature: [gas: ?]
        gasLimitsForFunctionSelectors[0x7f548071] = 600_000;
        functionSelectorNames[0x7f548071] = "delegateToBySignature";

        // transferToStaker: [gas: ?]
        gasLimitsForFunctionSelectors[0x27167d10] = 800_000;
    }

    function decodeFunctionSelector(bytes memory message) public returns (bytes4) {
        return FunctionSelectorDecoder.decodeFunctionSelector(message);
    }

    function setFunctionSelectorName(
        bytes4 functionSelector,
        string memory _name
    ) public onlyOwner returns (string memory) {
        return functionSelectorNames[functionSelector] = _name;
    }

    function getFunctionSelectorName(bytes4 functionSelector) public view returns (string memory) {
        return functionSelectorNames[functionSelector];
    }

    function setGasLimitsForFunctionSelectors(
        bytes4[] memory functionSelectors,
        uint256[] memory gasLimits
    ) public onlyOwner {

        require(functionSelectors.length == gasLimits.length, "input arrays must have the same length");

        for (uint256 i = 0; i < gasLimits.length; ++i) {
            gasLimitsForFunctionSelectors[functionSelectors[i]] = gasLimits[i];
            emit SetGasLimitForFunctionSelector(functionSelectors[i], gasLimits[i]);
        }
    }

    function getGasLimitForFunctionSelector(bytes4 functionSelector) public view returns (uint256) {
        return gasLimitsForFunctionSelectors[functionSelector];
    }
}

