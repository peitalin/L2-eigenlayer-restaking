//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {OwnableUpgradeable} from "@openzeppelin-v5-contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IAdminable {
    function addAdmin(address a) external;
    function removeAdmin(address a) external;
    function isAdmin(address a) external view returns(bool);
}

contract Adminable is IAdminable, OwnableUpgradeable {

    mapping(address => bool) private admins;

    function __Adminable_init() internal initializer {
        OwnableUpgradeable.__Ownable_init(msg.sender);
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
