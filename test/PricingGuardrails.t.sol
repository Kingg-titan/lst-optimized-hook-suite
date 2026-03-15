// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {PricingGuardrails} from "src/modules/PricingGuardrails.sol";

contract GuardrailHarness {
    using PricingGuardrails for PricingGuardrails.GuardrailState;

    PricingGuardrails.GuardrailState internal state;

    function beginCooldown(PricingGuardrails.GuardrailConfig memory cfg, uint40 timestamp) external {
        state.beginCooldown(cfg, timestamp);
    }

    function checkpointTick(int24 tick_, uint40 timestamp) external {
        state.checkpointTick(tick_, timestamp);
    }

    function readState() external view returns (PricingGuardrails.GuardrailState memory) {
        return state;
    }

    function enforce(PricingGuardrails.GuardrailConfig memory cfg, uint40 timestamp, uint256 amountIn, int24 tick)
        external
        view
        returns (bool constrained)
    {
        return PricingGuardrails.enforce(cfg, state, timestamp, amountIn, tick);
    }
}

contract PricingGuardrailsTest is Test {
    GuardrailHarness internal harness;
    PricingGuardrails.GuardrailConfig internal cfg;

    function setUp() public {
        harness = new GuardrailHarness();
        cfg = PricingGuardrails.GuardrailConfig({
            maxAmountIn: 10 ether,
            cooldownMaxAmountIn: 1 ether,
            maxImpactBps: 120,
            cooldownMaxImpactBps: 30,
            cooldownSeconds: 30,
            hysteresisSeconds: 10
        });
    }

    function testCooldownUsesTighterAmountLimit() public {
        harness.checkpointTick(100, uint40(block.timestamp));
        harness.beginCooldown(cfg, uint40(block.timestamp));

        vm.expectRevert();
        harness.enforce(cfg, uint40(block.timestamp), 2 ether, 100);
    }

    function testCooldownBoundaryOpenAtEnd() public {
        harness.checkpointTick(100, uint40(block.timestamp));
        harness.beginCooldown(cfg, uint40(block.timestamp));

        bool constrained = harness.enforce(cfg, uint40(block.timestamp + cfg.cooldownSeconds), 2 ether, 100);
        assertTrue(!constrained);
    }

    function testMaxImpactBoundary() public {
        harness.checkpointTick(1000, uint40(block.timestamp));
        harness.enforce(cfg, uint40(block.timestamp), 1 ether, 1120);

        vm.expectRevert();
        harness.enforce(cfg, uint40(block.timestamp), 1 ether, 1121);
    }

    function testFuzzValidInputsDoNotRevert(uint96 amount, int24 tickDelta) public {
        harness.checkpointTick(1000, uint40(block.timestamp));

        uint256 boundedAmount = uint256(amount) % cfg.maxAmountIn;
        int24 cap = int24(uint24(cfg.maxImpactBps));
        int24 boundedTick = 1000 + int24((tickDelta % cap));

        harness.enforce(cfg, uint40(block.timestamp), boundedAmount, boundedTick);
    }
}
