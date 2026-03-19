// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

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
import {PricingGuardrails} from "src/modules/PricingGuardrails.sol";
import {YieldDistributionController} from "src/modules/YieldDistributionController.sol";

import {MockPoolManager} from "test/mocks/MockPoolManager.sol";

contract LSTOptimizedHookTest is Test {
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

        // Prime index state with first callback.
        _beforeSwap(0.01 ether, 0);
        _afterSwap(0);
    }

    function testSwapAllowedWhenIndexConstant() public {
        _beforeSwap(0.2 ether, 10);
        assertEq(hook.constrainedSwapCount(poolId), 0);
    }

    function testRebaseTriggersCooldownAndRecordsYield() public {
        rebasing.rebaseByBps(100);
        _beforeSwap(0.25 ether, 10);

        assertEq(hook.constrainedSwapCount(poolId), 1);

        YieldDistributionController.PoolAccounting memory accounting = controller.getPoolAccounting(poolId);
        assertGt(accounting.cumulativeYieldRaw, 0);
        assertGt(accounting.cumulativeDistributedRaw, 0);
    }

    function testSwapRevertsWhenAmountExceedsCooldownLimit() public {
        rebasing.rebaseByBps(100);
        _expectBeforeSwapRevert(0.6 ether, 0);
    }

    function testCooldownBoundaryOpenAtEnd() public {
        rebasing.rebaseByBps(100);
        _beforeSwap(0.25 ether, 0);

        vm.warp(block.timestamp + 30);
        _beforeSwap(1 ether, 0);
    }

    function testExtremeIndexDeltaReverts() public {
        rebasing.rebaseByBps(1000);
        _expectBeforeSwapRevert(0.1 ether, 0);
    }

    function testAfterSwapCheckpointsTick() public {
        _beforeSwap(0.1 ether, 20);
        _afterSwap(33);

        (uint40 cooldownEnd, uint40 hysteresisEnd, int24 lastObservedTick, uint40 lastObservedAt) = _guardrailState();
        assertEq(lastObservedTick, 33);
        assertGt(lastObservedAt, 0);
        cooldownEnd;
        hysteresisEnd;
    }

    function testPoolNotConfiguredReverts() public {
        YieldDistributionController freshController = new YieldDistributionController(address(this));

        address flags = address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (0x5555 << 144));
        bytes memory constructorArgs = abi.encode(IPoolManager(address(mockPoolManager)), freshController);
        deployCodeTo("LSTOptimizedHook.sol:LSTOptimizedHook", constructorArgs, flags);

        LSTOptimizedHook freshHook = LSTOptimizedHook(flags);
        freshController.setHook(address(freshHook));

        vm.prank(address(mockPoolManager));
        vm.expectRevert();
        freshHook.beforeSwap(address(this), poolKey, _swapParams(0.1 ether), bytes(""));
    }

    function testMismatchedTokenConfigReverts() public {
        YieldDistributionController.PoolConfig memory cfg = controller.getPoolConfig(poolId);
        cfg.rebasingToken = address(quote);
        controller.setPoolConfig(poolId, cfg);

        _expectBeforeSwapRevert(0.1 ether, 0);
    }

    function testPermissionBitMismatchExpectations() public {
        vm.expectRevert();
        new LSTOptimizedHook(IPoolManager(address(mockPoolManager)), controller);
    }

    function testGetHookPermissions() public view {
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        assertTrue(permissions.beforeSwap);
        assertTrue(permissions.afterSwap);
        assertTrue(!permissions.beforeInitialize);
    }

    function testConfiguredTokenValidationAlternateBranch() public {
        MockNonRebasingLST quote2 = new MockNonRebasingLST("Quote 2", "q2");
        MockRebasingLST rebasing2 = new MockRebasingLST("Rebase 2", "r2", 2_000);
        rebasing2.mint(address(mockPoolManager), 1_000 ether);

        // Force the `rebasingTokenIsCurrency0 == false` branch deterministically.
        PoolKey memory poolKey2 =
            PoolKey(Currency.wrap(address(quote2)), Currency.wrap(address(rebasing2)), 3000, 60, IHooks(hook));
        bool rebasingIsCurrency0ForPool2 = false;
        PoolId poolId2 = poolKey2.toId();

        YieldDistributionController.PoolConfig memory cfg = controller.getPoolConfig(poolId);
        cfg.rebasingToken = address(rebasing2);
        cfg.rebasingTokenIsCurrency0 = rebasingIsCurrency0ForPool2;
        controller.setPoolConfig(poolId2, cfg);

        _beforeSwapFor(poolKey2, poolId2, rebasingIsCurrency0ForPool2, 0.1 ether, 0);
    }

    function testConfiguredTokenValidationAlternateBranchMismatchReverts() public {
        MockNonRebasingLST quote2 = new MockNonRebasingLST("Quote 2", "q2");
        MockRebasingLST rebasing2 = new MockRebasingLST("Rebase 2", "r2", 2_000);
        rebasing2.mint(address(mockPoolManager), 1_000 ether);

        PoolKey memory poolKey2 =
            PoolKey(Currency.wrap(address(quote2)), Currency.wrap(address(rebasing2)), 3000, 60, IHooks(hook));
        PoolId poolId2 = poolKey2.toId();

        YieldDistributionController.PoolConfig memory cfg = controller.getPoolConfig(poolId);
        cfg.rebasingToken = address(quote2);
        cfg.rebasingTokenIsCurrency0 = false;
        controller.setPoolConfig(poolId2, cfg);

        _expectBeforeSwapRevertFor(poolKey2, poolId2, false, 0.1 ether, 0);
    }

    function _beforeSwap(uint256 amountIn, int24 tick) internal {
        _beforeSwapFor(poolKey, poolId, rebasingIsCurrency0, amountIn, tick);
    }

    function _expectBeforeSwapRevert(uint256 amountIn, int24 tick) internal {
        mockPoolManager.setSlot0(poolId, SQRT_PRICE_1_1, tick, 0, 3000);

        vm.expectRevert();
        vm.prank(address(mockPoolManager));
        hook.beforeSwap(address(this), poolKey, _swapParams(amountIn), bytes(""));
    }

    function _expectBeforeSwapRevertFor(PoolKey memory key, PoolId id, bool zeroForOne, uint256 amountIn, int24 tick)
        internal
    {
        mockPoolManager.setSlot0(id, SQRT_PRICE_1_1, tick, 0, 3000);

        vm.expectRevert();
        vm.prank(address(mockPoolManager));
        hook.beforeSwap(
            address(this),
            key,
            SwapParams({zeroForOne: zeroForOne, amountSpecified: -int256(amountIn), sqrtPriceLimitX96: 0}),
            bytes("")
        );
    }

    function _afterSwap(int24 tick) internal {
        mockPoolManager.setSlot0(poolId, SQRT_PRICE_1_1, tick, 0, 3000);

        vm.prank(address(mockPoolManager));
        hook.afterSwap(address(this), poolKey, _swapParams(0.05 ether), BalanceDelta.wrap(0), bytes(""));
    }

    function _guardrailState()
        internal
        view
        returns (uint40 cooldownEnd, uint40 hysteresisEnd, int24 lastObservedTick, uint40 lastObservedAt)
    {
        PricingGuardrails.GuardrailState memory state = hook.getGuardrailState(poolId);
        return (state.cooldownEnd, state.hysteresisEnd, state.lastObservedTick, state.lastObservedAt);
    }

    function _swapParams(uint256 amountIn) internal view returns (SwapParams memory) {
        return SwapParams({zeroForOne: rebasingIsCurrency0, amountSpecified: -int256(amountIn), sqrtPriceLimitX96: 0});
    }

    function _beforeSwapFor(PoolKey memory key, PoolId id, bool zeroForOne, uint256 amountIn, int24 tick) internal {
        mockPoolManager.setSlot0(id, SQRT_PRICE_1_1, tick, 0, 3000);

        vm.prank(address(mockPoolManager));
        hook.beforeSwap(
            address(this),
            key,
            SwapParams({zeroForOne: zeroForOne, amountSpecified: -int256(amountIn), sqrtPriceLimitX96: 0}),
            bytes("")
        );
    }
}
