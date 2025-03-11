// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

contract GasLimits {
    function getGasLimits() public pure returns (
        bytes4[] memory,
        uint256[] memory
    ) {
        // set GasLimits
        uint256[] memory gasLimits = new uint256[](7);
        gasLimits[0] = 560_000; // deposit                           [gas: 543,362]
        // note: set manual gasLimit for deposit + mint EigenAgent:  [gas: 851,384] ~400k mint + 450k deposit
        gasLimits[1] = 300_000; // mintEigenAgent                    [gas: 284,571]
        gasLimits[2] = 580_000; // queueWithdrawals                  [gas: 556,767]
        gasLimits[3] = 630_000; // completeWithdrawal + transferToL2 [gas: 607,404]
        gasLimits[4] = 400_000; // delegateTo                        [gas: 372,427]
        gasLimits[5] = 650_000; // undelegate                        [gas: 632,561]
        gasLimits[6] = 590_000; // processClaim + transferToL2       [gas: 561,726]

        bytes4[] memory functionSelectors = new bytes4[](7);
        functionSelectors[0] = 0xe7a050aa;
        // cast sig "depositIntoStrategy(address,address,uint256)" == 0xe7a050aa
        functionSelectors[1] = 0xcc15a557;
        // cast sig "mintEigenAgent(bytes)" == 0xcc15a557
        functionSelectors[2] = 0x0dd8dd02;
        // cast sig "queueWithdrawals((address[],uint256[],address)[])" == 0x0dd8dd02
        functionSelectors[3] = 0xe4cc3f90;
        // cast sig "completeQueuedWithdrawal((address,address,address,uint256,uint32,address[],uint256[]),address[],bool)" == 0xe4cc3f90
        functionSelectors[4] = 0xeea9064b;
        // cast sig "delegateTo(address,(bytes,uint256),bytes32)" == 0xeea9064b
        functionSelectors[5] = 0xda8be864;
        // cast sig "undelegate(address)" == 0xda8be864
        functionSelectors[6] = 0x3ccc861d;
        // cast sig "processClaim((uint32,uint32,bytes,(address,bytes32),uint32[],bytes[],(address,uint256)[]), address)" == 0x3ccc861d

        return (functionSelectors, gasLimits);
    }
}
