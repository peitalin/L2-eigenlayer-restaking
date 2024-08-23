// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

interface IEigenAgent6551 {

    function beforeExecute(bytes calldata data) external returns (bytes4);

    function afterExecute(
        bytes calldata data,
        bool success,
        bytes memory result
    ) external returns (bytes4);
}
