// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {console} from "forge-std/Test.sol";

contract TestErrorHandlers {

    function strEq(string memory s1, string memory s2) public pure returns (bool) {
        return keccak256(abi.encode(s1)) == keccak256(abi.encode(s2));
    }

    function catchErrorStr(string memory s1, string memory s2) public pure returns (bool) {
        if (strEq(s1, s2)) {
            console.log(s1);
            return true;
        } else {
            return false;
        }
    }

    function catchErrorBytes(bytes memory b1, string memory s2) public pure returns (bool) {
        string memory s1 = abi.decode(b1, (string));
        if (strEq(s1, s2)) {
            console.log(s1);
            return true;
        } else {
            return false;
        }
    }

    function test_deploy_script_helpers() public {}
}

