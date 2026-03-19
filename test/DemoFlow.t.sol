// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

import {LSTOptimizedHook} from "src/LSTOptimizedHook.sol";
import {MockRebasingLST} from "src/mocks/MockRebasingLST.sol";
import {MockNonRebasingLST} from "src/mocks/MockNonRebasingLST.sol";
import {YieldDistributionController} from "src/modules/YieldDistributionController.sol";

import {MockPoolManager} from "test/mocks/MockPoolManager.sol";

contract DemoFlowTest is Test {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    MockPoolManager internal mockPoolManager;
    MockRebasingLST internal rebasing;
    MockNonRebasingLST internal quote;
    YieldDistributionController internal controller;
    LSTOptimizedHook internal hook;
    PoolKey internal poolKey;
    PoolId internal poolId;
    bool internal rebasingIsCurrency0;

    function setUp() public {
        mockPoolManager = new MockPoolManager();
        rebasing = new MockRebasingLST("Mock stETH", "mstETH", 2_000);
        quote = new MockNonRebasingLST("Mock qUSD", "mqUSD");
        controller = new YieldDistributionController(address(this));

        address flags = address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (0x4444 << 144));
        bytes memory constructorArgs = abi.encode(IPoolManager(address(mockPoolManager)), controller);
        deployCodeTo("LSTOptimizedHook.sol:LSTOptimizedHook", constructorArgs, flags);
        hook = LSTOptimizedHook(flags);
        controller.setHook(address(hook));

        Currency rebasingCurrency = Currency.wrap(address(rebasing));
        Currency quoteCurrency = Currency.wrap(address(quote));

        if (rebasingCurrency < quoteCurrency) {
            poolKey = PoolKey(rebasingCurrency, quoteCurrency, 3000, 60, IHooks(hook));
            rebasingIsCurrency0 = true;
        } else {
            poolKey = PoolKey(quoteCurrency, rebasingCurrency, 3000, 60, IHooks(hook));
            rebasingIsCurrency0 = false;
        }
        poolId = poolKey.toId();

        YieldDistributionController.PoolConfig memory cfg = YieldDistributionController.PoolConfig({
            enabled: true,
            rebasingToken: address(rebasing),
            rebasingTokenIsCurrency0: rebasingIsCurrency0,
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

        controller.setPoolConfig(poolId, cfg);
        rebasing.mint(address(mockPoolManager), 2_000 ether);
        mockPoolManager.setSlot0(poolId, SQRT_PRICE_1_1, 0, 0, 3000);

        _beforeSwap(0.01 ether, 0);
        _afterSwap(0);
    }

    function testDemoLifecycleSummary() public {
        console2.log("== Demo: LST-Optimized Hook Lifecycle ==");
        console2.log("poolId", vm.toString(PoolId.unwrap(poolId)));
        console2.log("rebasing token", address(rebasing));
        console2.log("quote token", address(quote));

        console2.log("-- Phase A: Normal trading (no rebase) --");
        uint256 constrainedBefore = hook.constrainedSwapCount(poolId);
        _beforeSwap(0.2 ether, 10);
        _afterSwap(10);
        uint256 constrainedAfterNormal = hook.constrainedSwapCount(poolId);
        assertEq(constrainedBefore, constrainedAfterNormal);
        console2.log("normal trade constrained count delta", constrainedAfterNormal - constrainedBefore);

        console2.log("-- Phase B: Rebase stress window --");
        uint256 indexBefore = rebasing.index();
        rebasing.rebaseByBps(100);
        uint256 indexAfter = rebasing.index();
        console2.log("index before", indexBefore);
        console2.log("index after", indexAfter);
        assertGt(indexAfter, indexBefore);

        _beforeSwap(0.25 ether, 12);
        _afterSwap(12);
        uint256 constrainedAfterRebase = hook.constrainedSwapCount(poolId);
        assertEq(constrainedAfterRebase, constrainedAfterNormal + 1);
        console2.log("constrained swaps after rebase", constrainedAfterRebase);

        mockPoolManager.setSlot0(poolId, SQRT_PRICE_1_1, 12, 0, 3000);
        vm.expectRevert();
        vm.prank(address(mockPoolManager));
        hook.beforeSwap(
            address(this),
            poolKey,
            SwapParams({zeroForOne: rebasingIsCurrency0, amountSpecified: -int256(0.6 ether), sqrtPriceLimitX96: 0}),
            bytes("")
        );
        console2.log("oversized cooldown swap blocked");

        vm.warp(block.timestamp + 31);
        _beforeSwap(1 ether, 13);
        _afterSwap(13);
        console2.log("post-cooldown swap allowed");

        YieldDistributionController.PoolAccounting memory accounting = controller.getPoolAccounting(poolId);
        console2.log("cumulative yield raw", accounting.cumulativeYieldRaw);
        console2.log("cumulative distributed raw", accounting.cumulativeDistributedRaw);
        assertGt(accounting.cumulativeYieldRaw, 0);
        assertGt(accounting.cumulativeDistributedRaw, 0);
    }

    function testRebaseTriggersCooldownAndConstrainedSwapCounter() public {
        uint256 constrainedBefore = hook.constrainedSwapCount(poolId);
        rebasing.rebaseByBps(100);

        _beforeSwap(0.2 ether, 8);
        _afterSwap(8);

        uint256 constrainedAfter = hook.constrainedSwapCount(poolId);
        assertEq(constrainedAfter, constrainedBefore + 1);
    }

    function _beforeSwap(uint256 amountIn, int24 tick) internal {
        mockPoolManager.setSlot0(poolId, SQRT_PRICE_1_1, tick, 0, 3000);
        vm.prank(address(mockPoolManager));
        hook.beforeSwap(
            address(this),
            poolKey,
            SwapParams({zeroForOne: rebasingIsCurrency0, amountSpecified: -int256(amountIn), sqrtPriceLimitX96: 0}),
            bytes("")
        );
    }

    function _afterSwap(int24 tick) internal {
        mockPoolManager.setSlot0(poolId, SQRT_PRICE_1_1, tick, 0, 3000);
        vm.prank(address(mockPoolManager));
        hook.afterSwap(
            address(this),
            poolKey,
            SwapParams({zeroForOne: rebasingIsCurrency0, amountSpecified: -int256(0.05 ether), sqrtPriceLimitX96: 0}),
            BalanceDelta.wrap(0),
            bytes("")
        );
    }
}
