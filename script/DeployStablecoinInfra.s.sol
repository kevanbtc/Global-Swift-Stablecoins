// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {RailRegistry} from "../contracts/settlement/rails/RailRegistry.sol";
import {ERC20Rail} from "../contracts/settlement/rails/ERC20Rail.sol";
import {NativeRail} from "../contracts/settlement/rails/NativeRail.sol";
import {ExternalRail} from "../contracts/settlement/rails/ExternalRail.sol";

import {StablecoinRegistry} from "../contracts/settlement/stable/StablecoinRegistry.sol";
import {PoRGuard} from "../contracts/settlement/stable/PoRGuard.sol";
import {StablecoinAwareERC20Rail} from "../contracts/settlement/stable/StablecoinAwareERC20Rail.sol";
import {CCTPExternalRail} from "../contracts/settlement/stable/CCTPExternalRail.sol";
import {CCIPRail} from "../contracts/settlement/stable/CCIPRail.sol";
import {StablecoinRouter} from "../contracts/settlement/stable/StablecoinRouter.sol";

contract DeployStablecoinInfra is Script {
    // Example keys (keccak of readable labels)
    bytes32 constant KEY_ERC20 = keccak256("ERC20_RAIL");
    bytes32 constant KEY_NATIVE = keccak256("NATIVE_RAIL");
    bytes32 constant KEY_EXT   = keccak256("EXTERNAL_RAIL");
    bytes32 constant KEY_GUARDED = keccak256("GUARDED_ERC20_RAIL");
    bytes32 constant KEY_CCTP  = keccak256("USDC_CCTP");
    bytes32 constant KEY_CCIP  = keccak256("CCIP_RAIL");

    function run() external {
        vm.startBroadcast();

        address admin = msg.sender;
        address exec = msg.sender; // replace with dedicated executor in prod

        RailRegistry registry = new RailRegistry(admin);

        // Base rails
        ERC20Rail erc20Rail = new ERC20Rail(admin);
        NativeRail nativeRail = new NativeRail(admin);
        ExternalRail extRail = new ExternalRail(admin, exec);

        // Stablecoin components
        StablecoinRegistry scReg = new StablecoinRegistry(admin);
        PoRGuard guard = new PoRGuard(address(scReg));
        StablecoinAwareERC20Rail guardedErc20 = new StablecoinAwareERC20Rail(admin, address(guard));
        CCTPExternalRail cctpRail = new CCTPExternalRail(admin, exec, 0);
        CCIPRail ccipRail = new CCIPRail(admin, exec);

        // Router
        StablecoinRouter router = new StablecoinRouter(admin, address(registry));

        // Register rails
        registry.set(KEY_ERC20, address(erc20Rail));
        registry.set(KEY_NATIVE, address(nativeRail));
        registry.set(KEY_EXT, address(extRail));
        registry.set(KEY_CCTP, address(cctpRail));
        registry.set(KEY_CCIP, address(ccipRail));
        registry.set(KEY_GUARDED, address(guardedErc20));

        // Example: route all tokens to guarded ERC20 by default (optional)
        // In practice you will call router.setDefaultRail(token, KEY_ERC20) per token

        // Log addresses
        console2.log("RailRegistry:", address(registry));
        console2.log("ERC20Rail:", address(erc20Rail));
        console2.log("GuardedERC20Rail:", address(guardedErc20));
        console2.log("NativeRail:", address(nativeRail));
        console2.log("ExternalRail:", address(extRail));
        console2.log("CCTPExternalRail:", address(cctpRail));
    console2.log("CCIPRail:", address(ccipRail));
    console2.log("GuardedERC20 key:");
    console2.logBytes32(KEY_GUARDED);
        console2.log("StablecoinRegistry:", address(scReg));
        console2.log("PoRGuard:", address(guard));
        console2.log("StablecoinRouter:", address(router));

        vm.stopBroadcast();
    }
}
