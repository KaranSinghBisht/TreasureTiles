// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {TreasureTiles} from "../src/TreasureTiles.sol";

contract Deploy is Script {
    // Base Sepolia RandomnessSender (proxy)
    address constant RANDOMNESS_SENDER =
        0xf4e080Db4765C856c0af43e4A8C4e31aA3b48779;

    function run() external {
        vm.startBroadcast();
        TreasureTiles t = new TreasureTiles(RANDOMNESS_SENDER);
        vm.stopBroadcast();
        console2.log("TreasureTiles deployed at:", address(t));
    }
}
