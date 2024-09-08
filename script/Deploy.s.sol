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

        router = block.chainid == 84532 ? 0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93 : 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59;
        link = block.chainid == 84532 ? 0xE4aB69C077896252FAFBD49EFD26B5D171A32410 : 0x779877A7B0D9E8603169DdbD7836e478b4624789;

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

        console.log(address(hyperFungible));
        console.log(address(hyperLoop));

        vm.stopBroadcast();
    }
}
