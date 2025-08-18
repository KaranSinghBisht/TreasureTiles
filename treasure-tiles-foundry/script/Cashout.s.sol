// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {TreasureTiles} from "../src/TreasureTiles.sol";

contract CashOut is Script {
    function run() external {
        address game = vm.envAddress("TREASURE_ADDR");
        uint256 id = vm.envUint("ROUND_ID");

        TreasureTiles t = TreasureTiles(payable(game));

        vm.startBroadcast();
        t.cashOut(id);
        vm.stopBroadcast();

        console2.log("Cashed out on round", id);
    }
}
