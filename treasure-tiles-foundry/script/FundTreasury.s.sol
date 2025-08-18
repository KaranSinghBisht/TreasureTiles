// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

interface ITreasureTiles {
    function fund() external payable;
}

contract FundTreasury is Script {
    function run() external {
        address game = vm.envAddress("TREASURE_ADDR");
        uint256 amount = vm.envUint("FUND_WEI"); // e.g., 10000000000000000 for 0.01 ether

        vm.startBroadcast();
        ITreasureTiles(game).fund{value: amount}();
        vm.stopBroadcast();

        console2.log("Funded treasury:", game, amount);
    }
}
