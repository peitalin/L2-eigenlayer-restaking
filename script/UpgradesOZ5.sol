
pragma solidity 0.8.25;

import {ERC1967Utils} from "@openzeppelin-v5-contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Vm} from "forge-std/Vm.sol";
import {Script} from "forge-std/Script.sol";

contract UpgradesOZ5 is Script {

    /// @notice Workaround to get the ProxyAdmin address for OZ5
    /// https://forum.openzeppelin.com/t/how-to-easily-get-the-proxyadmin-address-of-the-transparentupgradeableproxy-v5/38214/2
    /// @param TUPproxy address of the TransparentUpgradeableProxy
    /// @return proxyAdmin address of the ProxyAdmin
    function getProxyAdminOZ5(address TUPproxy) internal view returns (address) {
        address CHEATCODE_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
        Vm vm = Vm(CHEATCODE_ADDRESS);

        bytes32 adminSlot = vm.load(TUPproxy, ERC1967Utils.ADMIN_SLOT);
        return address(uint160(uint256(adminSlot)));
    }
}