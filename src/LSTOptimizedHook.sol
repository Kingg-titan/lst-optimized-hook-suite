// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {IRebasingIndexToken} from "./interfaces/IRebasingIndexToken.sol";
import {RebaseAccountingModule} from "./modules/RebaseAccountingModule.sol";
import {PricingGuardrails} from "./modules/PricingGuardrails.sol";
import {YieldDistributionController} from "./modules/YieldDistributionController.sol";

contract LSTOptimizedHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using RebaseAccountingModule for RebaseAccountingModule.PoolIndexState;
    using PricingGuardrails for PricingGuardrails.GuardrailState;
    using CurrencyLibrary for Currency;

    error PoolNotConfigured();
    error RebasingTokenMismatch(address configured, address token0, address token1);

    event RebaseDetected(
        bytes32 indexed poolId,
        uint256 previousIndex,
        uint256 nextIndex,
        uint256 yieldDeltaRaw,
        uint256 distributedRaw,
        uint40 cooldownEnd
    );

    event GuardrailCheck(
        bytes32 indexed poolId, address indexed sender, uint256 amountSpecifiedAbs, bool constrained, int24 observedTick
    );

    YieldDistributionController public immutable controller;

    mapping(PoolId => RebaseAccountingModule.PoolIndexState) public indexState;
    mapping(PoolId => PricingGuardrails.GuardrailState) private guardrailState;

    mapping(PoolId => uint256) public constrainedSwapCount;

    constructor(IPoolManager _poolManager, YieldDistributionController _controller) BaseHook(_poolManager) {
        controller = _controller;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function getGuardrailState(PoolId poolId) external view returns (PricingGuardrails.GuardrailState memory) {
        return guardrailState[poolId];
    }

    function _beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        PoolId poolId = key.toId();
        uint256 amountSpecifiedAbs = _absAmountSpecified(params.amountSpecified);
        int24 currentTick;
        bool constrained;

        {
            YieldDistributionController.PoolConfig memory cfg = controller.getPoolConfig(poolId);
            if (!cfg.enabled) revert PoolNotConfigured();

            _validateConfiguredToken(cfg, key);

            PricingGuardrails.GuardrailConfig memory guardrailCfg = _guardrailConfig(cfg);
            PricingGuardrails.GuardrailState storage runtime = guardrailState[poolId];
            _applyRebaseTransition(poolId, cfg, guardrailCfg, runtime);

            (, currentTick,,) = poolManager.getSlot0(poolId);
            constrained =
                PricingGuardrails.enforce(guardrailCfg, runtime, uint40(block.timestamp), amountSpecifiedAbs, currentTick);

            if (constrained) {
                constrainedSwapCount[poolId] += 1;
            }
        }

        _emitGuardrailCheck(poolId, sender, amountSpecifiedAbs, constrained, currentTick);

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(address, PoolKey calldata key, SwapParams calldata, BalanceDelta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        PoolId poolId = key.toId();

        // If misconfigured pools call into the hook, avoid reverting in afterSwap and just checkpoint.
        (, int24 latestTick,,) = poolManager.getSlot0(poolId);
        guardrailState[poolId].checkpointTick(latestTick, uint40(block.timestamp));

        return (BaseHook.afterSwap.selector, 0);
    }

    function _validateConfiguredToken(YieldDistributionController.PoolConfig memory cfg, PoolKey calldata key)
        internal
        pure
    {
        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);

        address configuredToken = cfg.rebasingToken;
        if (cfg.rebasingTokenIsCurrency0) {
            if (configuredToken != token0) {
                revert RebasingTokenMismatch(configuredToken, token0, token1);
            }
        } else {
            if (configuredToken != token1) {
                revert RebasingTokenMismatch(configuredToken, token0, token1);
            }
        }
    }

    function _guardrailConfig(YieldDistributionController.PoolConfig memory cfg)
        internal
        pure
        returns (PricingGuardrails.GuardrailConfig memory guardrailCfg)
    {
        guardrailCfg = PricingGuardrails.GuardrailConfig({
            maxAmountIn: cfg.maxAmountIn,
            cooldownMaxAmountIn: cfg.cooldownMaxAmountIn,
            maxImpactBps: cfg.maxImpactBps,
            cooldownMaxImpactBps: cfg.cooldownMaxImpactBps,
            cooldownSeconds: cfg.cooldownSeconds,
            hysteresisSeconds: cfg.hysteresisSeconds
        });
    }

    function _applyRebaseTransition(
        PoolId poolId,
        YieldDistributionController.PoolConfig memory cfg,
        PricingGuardrails.GuardrailConfig memory guardrailCfg,
        PricingGuardrails.GuardrailState storage runtime
    ) internal {
        uint256 currentIndex = IRebasingIndexToken(cfg.rebasingToken).index();
        (bool indexChanged, uint256 previousIndex,) =
            indexState[poolId].detectAndUpdateIndex(currentIndex, cfg.maxIndexDeltaBps);

        if (!(indexChanged && previousIndex > 0)) {
            return;
        }

        uint256 rawReserve = IERC20(cfg.rebasingToken).balanceOf(address(poolManager));
        uint256 normalizedReserve = RebaseAccountingModule.normalizeDown(rawReserve, currentIndex);

        (uint256 yieldDeltaRaw, uint256 distributedRaw) =
            controller.recordYieldDelta(poolId, previousIndex, currentIndex, normalizedReserve);

        runtime.beginCooldown(guardrailCfg, uint40(block.timestamp));
        emit RebaseDetected(
            PoolId.unwrap(poolId), previousIndex, currentIndex, yieldDeltaRaw, distributedRaw, runtime.cooldownEnd
        );
    }

    function _absAmountSpecified(int256 amountSpecified) internal pure returns (uint256) {
        return amountSpecified < 0 ? uint256(-amountSpecified) : uint256(amountSpecified);
    }

    function _emitGuardrailCheck(
        PoolId poolId,
        address sender,
        uint256 amountSpecifiedAbs,
        bool constrained,
        int24 currentTick
    ) internal {
        emit GuardrailCheck(PoolId.unwrap(poolId), sender, amountSpecifiedAbs, constrained, currentTick);
    }
}
