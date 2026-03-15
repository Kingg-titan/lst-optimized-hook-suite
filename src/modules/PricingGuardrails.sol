// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library PricingGuardrails {
    error SwapAmountExceedsLimit(uint256 amountIn, uint256 maxAllowed);
    error TickMoveExceedsLimit(int24 previousTick, int24 currentTick, uint16 maxTickMove);

    struct GuardrailConfig {
        uint256 maxAmountIn;
        uint256 cooldownMaxAmountIn;
        uint16 maxImpactBps;
        uint16 cooldownMaxImpactBps;
        uint40 cooldownSeconds;
        uint40 hysteresisSeconds;
    }

    struct GuardrailState {
        uint40 cooldownEnd;
        uint40 hysteresisEnd;
        int24 lastObservedTick;
        uint40 lastObservedAt;
    }

    function beginCooldown(GuardrailState storage state, GuardrailConfig memory cfg, uint40 timestamp) internal {
        state.cooldownEnd = timestamp + cfg.cooldownSeconds;
        state.hysteresisEnd = state.cooldownEnd + cfg.hysteresisSeconds;
    }

    function inCooldown(GuardrailState memory state, uint40 timestamp) internal pure returns (bool) {
        return timestamp < state.cooldownEnd;
    }

    function currentLimits(GuardrailConfig memory cfg, GuardrailState memory state, uint40 timestamp)
        internal
        pure
        returns (uint256 maxAmountIn, uint16 maxImpactBps)
    {
        if (inCooldown(state, timestamp)) {
            maxAmountIn = cfg.cooldownMaxAmountIn;
            maxImpactBps = cfg.cooldownMaxImpactBps;
        } else {
            maxAmountIn = cfg.maxAmountIn;
            maxImpactBps = cfg.maxImpactBps;
        }
    }

    function enforce(
        GuardrailConfig memory cfg,
        GuardrailState memory state,
        uint40 timestamp,
        uint256 amountIn,
        int24 currentTick
    ) internal pure returns (bool constrained) {
        (uint256 maxAmountIn, uint16 maxImpactBps) = currentLimits(cfg, state, timestamp);

        if (maxAmountIn > 0 && amountIn > maxAmountIn) {
            revert SwapAmountExceedsLimit(amountIn, maxAmountIn);
        }

        if (state.lastObservedAt != 0 && maxImpactBps > 0) {
            int24 delta = currentTick - state.lastObservedTick;
            int24 absDelta = delta >= 0 ? delta : -delta;

            // Approximation: ~1 tick ~ 1 bps for small moves.
            if (uint24(absDelta) > uint24(maxImpactBps)) {
                revert TickMoveExceedsLimit(state.lastObservedTick, currentTick, maxImpactBps);
            }
        }

        constrained = inCooldown(state, timestamp);
    }

    function checkpointTick(GuardrailState storage state, int24 tick_, uint40 timestamp) internal {
        state.lastObservedTick = tick_;
        state.lastObservedAt = timestamp;
    }
}
