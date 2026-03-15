// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";

import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {EasyPosm} from "./utils/libraries/EasyPosm.sol";
import {BaseTest} from "./utils/BaseTest.sol";

import {LSTOptimizedHook} from "src/LSTOptimizedHook.sol";
import {MockRebasingLST} from "src/mocks/MockRebasingLST.sol";
import {YieldDistributionController} from "src/modules/YieldDistributionController.sol";

contract LSTOptimizedHookTest is BaseTest {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    MockRebasingLST internal rebasing;
    MockERC20 internal quote;

    LSTOptimizedHook internal hook;
    YieldDistributionController internal controller;

    PoolKey internal poolKey;
    PoolId internal poolId;

    bool internal rebasingIsCurrency0;

    uint256 internal positionId;

    uint40 internal constant COOLDOWN_SECONDS = 30;
    uint256 internal constant MAX_AMOUNT_IN = 5 ether;
    uint256 internal constant COOLDOWN_MAX_AMOUNT_IN = 0.5 ether;

    function setUp() public {
        deployArtifactsAndLabel();

        rebasing = new MockRebasingLST("Mock stETH", "mstETH", 2_000);
        quote = new MockERC20("Quote USD", "qUSD", 18);

        rebasing.mint(address(this), 1_000_000 ether);
        quote.mint(address(this), 1_000_000 ether);

        rebasing.approve(address(permit2), type(uint256).max);
        rebasing.approve(address(swapRouter), type(uint256).max);
        quote.approve(address(permit2), type(uint256).max);
        quote.approve(address(swapRouter), type(uint256).max);

        permit2.approve(address(rebasing), address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(rebasing), address(poolManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(quote), address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(quote), address(poolManager), type(uint160).max, type(uint48).max);

        controller = new YieldDistributionController(address(this));

        address flags = address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (0x4444 << 144));
        bytes memory constructorArgs = abi.encode(poolManager, controller);
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
            maxAmountIn: MAX_AMOUNT_IN,
            cooldownMaxAmountIn: COOLDOWN_MAX_AMOUNT_IN,
            maxImpactBps: 150,
            cooldownMaxImpactBps: 35,
            cooldownSeconds: COOLDOWN_SECONDS,
            hysteresisSeconds: 10
        });

        controller.setPoolConfig(poolId, cfg);

        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        int24 tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        int24 tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);

        uint128 liquidityAmount = 100e18;
        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        (positionId,) = positionManager.mint(
            poolKey,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            Constants.ZERO_BYTES
        );

        positionId;

        // Seed index and guardrail checkpoints.
        _swapExactIn(0.01 ether);
    }

    function testSwapAllowedWhenIndexConstant() public {
        _swapExactIn(0.2 ether);
        assertEq(hook.constrainedSwapCount(poolId), 0);
    }

    function testRebaseTriggersCooldownAndConstrainedSwapCounter() public {
        rebasing.rebaseByBps(100);

        _swapExactIn(0.25 ether);
        assertEq(hook.constrainedSwapCount(poolId), 1);

        YieldDistributionController.PoolAccounting memory accounting = controller.getPoolAccounting(poolId);
        assertGt(accounting.cumulativeYieldRaw, 0);
        assertGt(accounting.cumulativeDistributedRaw, 0);
    }

    function testSwapRevertsWhenAmountExceedsCooldownLimit() public {
        rebasing.rebaseByBps(100);

        vm.expectRevert();
        _swapExactIn(COOLDOWN_MAX_AMOUNT_IN + 1);
    }

    function testCooldownBoundaryOpenAtEnd() public {
        rebasing.rebaseByBps(100);
        _swapExactIn(0.25 ether);

        vm.warp(block.timestamp + COOLDOWN_SECONDS);
        _swapExactIn(1 ether);
    }

    function testMaxSwapBoundary() public {
        _swapExactIn(MAX_AMOUNT_IN);

        vm.expectRevert();
        _swapExactIn(MAX_AMOUNT_IN + 1);
    }

    function testExtremeIndexDeltaReverts() public {
        rebasing.rebaseByBps(1000);
        vm.expectRevert();
        _swapExactIn(0.1 ether);
    }

    function testUnauthorizedConfigChangeReverts() public {
        YieldDistributionController.PoolConfig memory cfg = controller.getPoolConfig(poolId);
        cfg.maxAmountIn = 1;

        vm.prank(address(0xBEEF));
        vm.expectRevert(YieldDistributionController.Unauthorized.selector);
        controller.setPoolConfig(poolId, cfg);
    }

    function testPermissionBitMismatchExpectations() public {
        vm.expectRevert();
        new LSTOptimizedHook(poolManager, controller);
    }

    function testDemoLifecycleSummary() public {
        _swapExactIn(0.1 ether);

        rebasing.rebaseByBps(120);
        vm.expectRevert();
        _swapExactIn(1 ether);

        vm.warp(block.timestamp + COOLDOWN_SECONDS + 1);
        _swapExactIn(0.5 ether);

        emit log_named_uint("indexAfter", rebasing.index());
        emit log_named_uint("constrainedSwapCount", hook.constrainedSwapCount(poolId));
    }

    function _swapExactIn(uint256 amountIn) internal returns (BalanceDelta swapDelta) {
        swapDelta = swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: rebasingIsCurrency0,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
    }
}
