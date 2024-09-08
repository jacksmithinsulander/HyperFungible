// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {HyperFungible} from "src/HyperFungible.sol";
import {HyperLoop} from "src/HyperLoop.sol";

contract Deploy is Script {
    uint256 pkey = vm.envUint("DEPLOYER_KEY");

    HyperFungible hyperFungible;
    HyperLoop hyperLoop;

    address link;
    address router;

    function run() public {
        vm.startBroadcast(pkey);

        hyperFungible = new HyperFungible(
            router,
            link,
            uint40(block.chainid)
        );

        hyperLoop = new HyperLoop(
            router,
            link,
            uint40(block.chainid)
        );

        vm.stopBroadcast();
    }
}
