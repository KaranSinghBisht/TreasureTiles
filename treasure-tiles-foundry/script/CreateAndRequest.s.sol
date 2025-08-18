// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {TreasureTiles} from "../src/TreasureTiles.sol";

contract CreateAndRequest is Script {
    uint8 constant ROWS = 6;
    uint8 constant COLS = 6;
    uint8 constant BOMBS = 8;
    uint32 constant CALLBACK_GAS = 250_000;
    uint256 constant STAKE = 0.01 ether;
    uint256 constant VRF_FEE_BUFFER = 0.01 ether;

    function run() external {
        address game = vm.envAddress("TREASURE_ADDR");
        // Cast via payable() because the contract has a receive() (payable).
        TreasureTiles t = TreasureTiles(payable(game));

        vm.startBroadcast();
        uint256 id = t.createRound{value: STAKE}(ROWS, COLS, BOMBS);
        console2.log("Round id:", id);
        t.requestSeedDirect{value: VRF_FEE_BUFFER}(id, CALLBACK_GAS);
        vm.stopBroadcast();

        console2.log("Requested VRF. Wait for fulfillment, then reveal tiles.");
    }
}
