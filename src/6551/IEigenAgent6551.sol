// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

interface IEigenAgent6551 {

    function approveStrategyManagerWithSignature(
        address _target,
        uint256 _value,
        bytes calldata _data,
        uint256 _expiry,
        bytes memory _signature
    ) external returns (bool);

    function beforeExecute(bytes calldata data) external returns (bytes4);

    function afterExecute(
        bytes calldata data,
        bool success,
        bytes memory result
    ) external returns (bytes4);
}
