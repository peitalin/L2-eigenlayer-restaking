// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {EigenAgent6551} from "../../src/6551/EigenAgent6551.sol";

contract EigenAgent6551TestUpgrade is EigenAgent6551 {

    function agentImplVersion() public virtual override returns (uint256) {
        return 2;
    }

}
