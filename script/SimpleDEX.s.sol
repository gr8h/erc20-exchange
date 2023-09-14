// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "src/SimpleDEX.sol";

contract SimpleDEXScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        console.log("Deployer address: %s", deployerAddress);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy SimpleDEX
        SimpleDEX dex = new SimpleDEX();
        // Add supported tokens
        dex.addSupportedToken(0x4a56cF1dC528C04DEe7638B69417Bec6884BFac7); // USDC
        dex.addSupportedToken(0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6); // WETH

        vm.stopBroadcast();
    }
}
