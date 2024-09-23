// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Adminable} from "../../src/utils/Adminable.sol";


contract ERC20Minter is Initializable, ERC20Upgradeable, Adminable {

    function initialize(
        string memory name,
        string memory symbol
    ) initializer public {
        ERC20Upgradeable.__ERC20_init(name, symbol);
        Adminable.__Adminable_init();
    }

    function mint(address to, uint256 amount) public onlyAdminOrOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public onlyOwner {
        _burn(from, amount);
    }

}