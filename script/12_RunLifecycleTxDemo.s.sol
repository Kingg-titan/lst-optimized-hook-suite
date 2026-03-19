// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

import {LSTOptimizedHook} from "src/LSTOptimizedHook.sol";
import {MockRebasingLST} from "src/mocks/MockRebasingLST.sol";
import {MockNonRebasingLST} from "src/mocks/MockNonRebasingLST.sol";
import {MockPoolManagerHarness} from "src/mocks/MockPoolManagerHarness.sol";
import {YieldDistributionController} from "src/modules/YieldDistributionController.sol";
import {PricingGuardrails} from "src/modules/PricingGuardrails.sol";

contract RunLifecycleTxDemo is Script {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    struct DemoContext {
        MockPoolManagerHarness poolManager;
        YieldDistributionController controller;
        LSTOptimizedHook hook;
        MockRebasingLST rebasing;
        MockNonRebasingLST quote;
        PoolKey poolKey;
        PoolId poolId;
        bool rebasingIsCurrency0;
        address deployer;
    }

    struct DemoSummary {
        uint256 indexBefore;
        uint256 indexAfter;
        uint256 cumulativeYieldRaw;
        uint256 cumulativeDistributedRaw;
    }

    function run() external {
        uint256 privateKey = _resolvePrivateKey();
        address deployer = vm.addr(privateKey);
        uint40 cooldownSeconds = uint40(vm.envOr("LIFECYCLE_COOLDOWN_SECONDS", uint256(35)));
        uint40 hysteresisSeconds = uint40(vm.envOr("LIFECYCLE_HYSTERESIS_SECONDS", uint256(10)));
        uint256 cooldownAdvanceTxs = vm.envOr("LIFECYCLE_ADVANCE_TXS", uint256(30));

        vm.startBroadcast(privateKey);
        DemoContext memory ctx = _deployAndConfigure(deployer, cooldownSeconds, hysteresisSeconds);
        DemoSummary memory summary = _executeLifecycle(ctx, cooldownAdvanceTxs);
        vm.stopBroadcast();

        _logSummary(ctx, summary);
    }

    function _resolvePrivateKey() internal view returns (uint256 privateKey) {
        privateKey = vm.envOr("PRIVATE_KEY", uint256(0));
        if (privateKey == 0) {
            privateKey = vm.envUint("SEPOLIA_PRIVATE_KEY");
        }
    }

    function _deployAndConfigure(address deployer, uint40 cooldownSeconds, uint40 hysteresisSeconds)
        internal
        returns (DemoContext memory ctx)
    {
        MockPoolManagerHarness poolManager = new MockPoolManagerHarness();
        YieldDistributionController controller = new YieldDistributionController(deployer);
        MockRebasingLST rebasing = new MockRebasingLST("Lifecycle stETH", "lstETH", 2_000);
        MockNonRebasingLST quote = new MockNonRebasingLST("Lifecycle qUSD", "lqUSD");

        uint160 flags = Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG;
        bytes memory constructorArgs = abi.encode(IPoolManager(address(poolManager)), controller);
        (address expectedAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(LSTOptimizedHook).creationCode, constructorArgs);

        LSTOptimizedHook hook = new LSTOptimizedHook{salt: salt}(IPoolManager(address(poolManager)), controller);
        require(address(hook) == expectedAddress, "hook address mismatch");

        controller.setHook(address(hook));

        (PoolKey memory poolKey, bool rebasingIsCurrency0) = _buildPoolKey(rebasing, quote, hook);
        PoolId poolId = poolKey.toId();

        YieldDistributionController.PoolConfig memory cfg =
            _buildPoolConfig(address(rebasing), rebasingIsCurrency0, cooldownSeconds, hysteresisSeconds);
        controller.setPoolConfig(poolId, cfg);

        rebasing.mint(address(poolManager), 2_000 ether);
        ctx = DemoContext({
            poolManager: poolManager,
            controller: controller,
            hook: hook,
            rebasing: rebasing,
            quote: quote,
            poolKey: poolKey,
            poolId: poolId,
            rebasingIsCurrency0: rebasingIsCurrency0,
            deployer: deployer
        });
    }

    function _executeLifecycle(DemoContext memory ctx, uint256 cooldownAdvanceTxs)
        internal
        returns (DemoSummary memory summary)
    {
        _setTick(ctx.poolManager, ctx.poolId, 0);
        _beforeSwap(ctx.poolManager, ctx.hook, ctx.poolKey, ctx.rebasingIsCurrency0, ctx.deployer, 0.01 ether, true);
        _afterSwap(ctx.poolManager, ctx.hook, ctx.poolKey, ctx.rebasingIsCurrency0, ctx.deployer, 0);

        // Phase A: Normal trade while index is constant.
        _setTick(ctx.poolManager, ctx.poolId, 10);
        _beforeSwap(ctx.poolManager, ctx.hook, ctx.poolKey, ctx.rebasingIsCurrency0, ctx.deployer, 0.2 ether, true);
        _afterSwap(ctx.poolManager, ctx.hook, ctx.poolKey, ctx.rebasingIsCurrency0, ctx.deployer, 10);

        // Phase B: Rebase and constrained trade.
        summary.indexBefore = ctx.rebasing.index();
        ctx.rebasing.rebaseByBps(100);
        summary.indexAfter = ctx.rebasing.index();

        _setTick(ctx.poolManager, ctx.poolId, 12);
        _beforeSwap(ctx.poolManager, ctx.hook, ctx.poolKey, ctx.rebasingIsCurrency0, ctx.deployer, 0.25 ether, true);
        _afterSwap(ctx.poolManager, ctx.hook, ctx.poolKey, ctx.rebasingIsCurrency0, ctx.deployer, 12);

        // Oversized swap should be blocked while still in cooldown.
        _setTick(ctx.poolManager, ctx.poolId, 12);
        _beforeSwap(ctx.poolManager, ctx.hook, ctx.poolKey, ctx.rebasingIsCurrency0, ctx.deployer, 0.6 ether, false);

        // Emit filler txs so the live chain advances block timestamp between constrained and post-cooldown phases.
        _advanceDemoBlocks(ctx.poolManager, cooldownAdvanceTxs);

        // Ensure local script simulation can continue into the post-cooldown path deterministically.
        PricingGuardrails.GuardrailState memory guardState = ctx.hook.getGuardrailState(ctx.poolId);
        if (vm.getBlockTimestamp() <= guardState.cooldownEnd) {
            vm.warp(uint256(guardState.cooldownEnd) + 1);
        }

        // Phase C: Post-cooldown swap allowed.
        _setTick(ctx.poolManager, ctx.poolId, 13);
        _beforeSwap(ctx.poolManager, ctx.hook, ctx.poolKey, ctx.rebasingIsCurrency0, ctx.deployer, 1 ether, true);
        _afterSwap(ctx.poolManager, ctx.hook, ctx.poolKey, ctx.rebasingIsCurrency0, ctx.deployer, 13);

        YieldDistributionController.PoolAccounting memory accounting = ctx.controller.getPoolAccounting(ctx.poolId);
        require(accounting.cumulativeYieldRaw > 0, "no yield delta");
        require(accounting.cumulativeDistributedRaw > 0, "no distributed yield");
        summary.cumulativeYieldRaw = accounting.cumulativeYieldRaw;
        summary.cumulativeDistributedRaw = accounting.cumulativeDistributedRaw;
    }

    function _buildPoolKey(MockRebasingLST rebasing, MockNonRebasingLST quote, LSTOptimizedHook hook)
        internal
        pure
        returns (PoolKey memory poolKey, bool rebasingIsCurrency0)
    {
        Currency rebasingCurrency = Currency.wrap(address(rebasing));
        Currency quoteCurrency = Currency.wrap(address(quote));

        if (rebasingCurrency < quoteCurrency) {
            poolKey = PoolKey(rebasingCurrency, quoteCurrency, 3000, 60, IHooks(hook));
            rebasingIsCurrency0 = true;
        } else {
            poolKey = PoolKey(quoteCurrency, rebasingCurrency, 3000, 60, IHooks(hook));
            rebasingIsCurrency0 = false;
        }
    }

    function _advanceDemoBlocks(MockPoolManagerHarness poolManager, uint256 count) internal {
        for (uint256 i = 0; i < count; i++) {
            poolManager.setRawSlot(bytes32(1000 + i), bytes32(1000 + i));
        }
    }

    function _logSummary(DemoContext memory ctx, DemoSummary memory summary) internal pure {
        console2.log("lifecycleDemo.poolId", vm.toString(PoolId.unwrap(ctx.poolId)));
        console2.log("lifecycleDemo.poolManager", address(ctx.poolManager));
        console2.log("lifecycleDemo.controller", address(ctx.controller));
        console2.log("lifecycleDemo.hook", address(ctx.hook));
        console2.log("lifecycleDemo.rebasing", address(ctx.rebasing));
        console2.log("lifecycleDemo.quote", address(ctx.quote));
        console2.log("lifecycleDemo.indexBefore", summary.indexBefore);
        console2.log("lifecycleDemo.indexAfter", summary.indexAfter);
        console2.log("lifecycleDemo.cumulativeYieldRaw", summary.cumulativeYieldRaw);
        console2.log("lifecycleDemo.cumulativeDistributedRaw", summary.cumulativeDistributedRaw);
    }

    function _setTick(MockPoolManagerHarness poolManager, PoolId poolId, int24 tick) internal {
        poolManager.setSlot0(poolId, SQRT_PRICE_1_1, tick, 0, 3000);
    }

    function _buildPoolConfig(
        address rebasingToken,
        bool rebasingIsCurrency0,
        uint40 cooldownSeconds,
        uint40 hysteresisSeconds
    ) internal pure returns (YieldDistributionController.PoolConfig memory cfg) {
        cfg.enabled = true;
        cfg.rebasingToken = rebasingToken;
        cfg.rebasingTokenIsCurrency0 = rebasingIsCurrency0;
        cfg.maxIndexDeltaBps = 600;
        cfg.yieldSplitBps = 2_000;
        cfg.distributionMode = YieldDistributionController.DistributionMode.Split;
        cfg.maxAmountIn = 5 ether;
        cfg.cooldownMaxAmountIn = 0.5 ether;
        cfg.maxImpactBps = 150;
        cfg.cooldownMaxImpactBps = 35;
        cfg.cooldownSeconds = cooldownSeconds;
        cfg.hysteresisSeconds = hysteresisSeconds;
    }

    function _beforeSwap(
        MockPoolManagerHarness poolManager,
        LSTOptimizedHook hook,
        PoolKey memory poolKey,
        bool zeroForOne,
        address sender,
        uint256 amountIn,
        bool expectedOk
    ) internal {
        (bool ok,) = poolManager.callBeforeSwap(
            address(hook),
            sender,
            poolKey,
            SwapParams({zeroForOne: zeroForOne, amountSpecified: -int256(amountIn), sqrtPriceLimitX96: 0})
        );
        require(ok == expectedOk, "unexpected beforeSwap result");
    }

    function _afterSwap(
        MockPoolManagerHarness poolManager,
        LSTOptimizedHook hook,
        PoolKey memory poolKey,
        bool zeroForOne,
        address sender,
        int24 tick
    ) internal {
        _setTick(poolManager, poolKey.toId(), tick);
        (bool ok,) = poolManager.callAfterSwap(
            address(hook),
            sender,
            poolKey,
            SwapParams({zeroForOne: zeroForOne, amountSpecified: -int256(0.05 ether), sqrtPriceLimitX96: 0})
        );
        require(ok, "afterSwap failed");
    }
}
