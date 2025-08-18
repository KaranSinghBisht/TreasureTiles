// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {TreasureTiles} from "../src/TreasureTiles.sol";

contract OpenTile is Script {
    function run() external {
        address game = vm.envAddress("TREASURE_ADDR");
        uint256 id = vm.envUint("ROUND_ID");
        uint8 row = uint8(vm.envUint("ROW"));
        uint8 col = uint8(vm.envUint("COL"));

        // contract has a payable receive(), so cast via payable()
        TreasureTiles t = TreasureTiles(payable(game));

        vm.startBroadcast();
        t.openTile(id, row, col);
        vm.stopBroadcast();

        // console2 has clean overloads; log in a few lines to avoid signature mismatches
        console2.log("Opened tile");
        console2.log("row", uint256(row));
        console2.log("col", uint256(col));
        console2.log("round", id);
    }
}
