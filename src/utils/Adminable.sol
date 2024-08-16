//SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Adminable is OwnableUpgradeable {

    mapping(address => bool) private admins;

    function __Adminable_init() internal initializer {
        OwnableUpgradeable.__Ownable_init();
    }

    modifier onlyAdmin() {
        require(admins[msg.sender] == true, "Not an admin");
        _;
    }

    modifier onlyAdminOrOwner() {
        require(admins[msg.sender] || isOwner(), "Not admin or owner");
        _;
    }

    function addAdmin(address a) external onlyOwner {
        admins[a] = true;
    }

    function removeAdmin(address a) external onlyOwner {
        admins[a] = false;
    }

    function isAdmin(address a) public view returns(bool) {
        return admins[a];
    }

    function isOwner() internal view returns(bool) {
        return owner() == msg.sender;
    }
}

contract MockAdminable is Adminable {

    constructor() {
        __Adminable_init();
    }

    function mockOnlyAdmin() public onlyAdmin returns (bool) {
        return true;
    }

    function mockOnlyAdminOrOwner() public onlyAdminOrOwner returns (bool) {
        return true;
    }
}
