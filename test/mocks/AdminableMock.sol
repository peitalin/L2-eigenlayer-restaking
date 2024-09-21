//SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Adminable} from "../../src/utils/Adminable.sol";

contract AdminableMock is Adminable {

    constructor() {
        __Adminable_init();
    }

    function mockIsOwner() public view returns (bool) {
        return isOwner();
    }

    function mockOnlyAdmin() public view onlyAdmin returns (bool) {
        return true;
    }

    function mockOnlyAdminOrOwner() public view onlyAdminOrOwner returns (bool) {
        return true;
    }
}
