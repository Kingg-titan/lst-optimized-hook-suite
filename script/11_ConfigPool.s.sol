// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {YieldDistributionController} from "src/modules/YieldDistributionController.sol";

contract ConfigPool is Script {
    using PoolIdLibrary for PoolKey;

    function run() external {
        uint256 privateKey = vm.envOr("PRIVATE_KEY", uint256(0));
        if (privateKey == 0) {
            privateKey = vm.envUint("SEPOLIA_PRIVATE_KEY");
        }

        address poolManager = vm.envOr("POOL_MANAGER", address(0));
        if (poolManager == address(0)) {
            poolManager = vm.envAddress("POOL_MANAGER_ADDRESS");
        }

        address hook = vm.envAddress("HOOK_ADDRESS");
        address controllerAddress = vm.envAddress("CONTROLLER_ADDRESS");

        address tokenA = vm.envOr("TOKEN_A", address(0));
        if (tokenA == address(0)) {
            tokenA = vm.envAddress("MOCK_REBASING_LST_ADDRESS");
        }

        address tokenB = vm.envOr("TOKEN_B", address(0));
        if (tokenB == address(0)) {
            tokenB = vm.envAddress("MOCK_NON_REBASING_LST_ADDRESS");
        }

        uint24 fee = uint24(vm.envUint("POOL_FEE"));
        int24 tickSpacing = int24(int256(vm.envInt("TICK_SPACING")));

        vm.startBroadcast(privateKey);

        PoolKey memory key;
        if (tokenA < tokenB) {
            key = PoolKey(Currency.wrap(tokenA), Currency.wrap(tokenB), fee, tickSpacing, IHooks(hook));
        } else {
            key = PoolKey(Currency.wrap(tokenB), Currency.wrap(tokenA), fee, tickSpacing, IHooks(hook));
        }

        PoolId poolId = key.toId();

        YieldDistributionController.PoolConfig memory cfg = YieldDistributionController.PoolConfig({
            enabled: true,
            rebasingToken: tokenA,
            rebasingTokenIsCurrency0: tokenA < tokenB,
            maxIndexDeltaBps: 600,
            yieldSplitBps: 2_000,
            distributionMode: YieldDistributionController.DistributionMode.Split,
            maxAmountIn: 5 ether,
            cooldownMaxAmountIn: 0.5 ether,
            maxImpactBps: 150,
            cooldownMaxImpactBps: 35,
            cooldownSeconds: 30,
            hysteresisSeconds: 10
        });

        YieldDistributionController(controllerAddress).setPoolConfig(poolId, cfg);

        bool tryPoolInitialize = vm.envOr("TRY_POOL_INITIALIZE", false);
        if (tryPoolInitialize) {
            // Optional initialize call if not initialized yet.
            try IPoolManager(poolManager).initialize(key, 79228162514264337593543950336) {
                console2.log("pool initialized");
            } catch {
                console2.log("pool initialize skipped (already initialized or unsupported call context)");
            }
        }

        vm.stopBroadcast();

        console2.log("poolId", vm.toString(PoolId.unwrap(poolId)));
    }
}
