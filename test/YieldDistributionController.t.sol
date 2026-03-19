// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

import {YieldDistributionController} from "src/modules/YieldDistributionController.sol";

contract YieldDistributionControllerTest is Test {
    YieldDistributionController internal controller;
    PoolId internal poolId;

    function setUp() public {
        controller = new YieldDistributionController(address(this));
        poolId = PoolId.wrap(keccak256("pool-1"));
    }

    function testSetHook() public {
        controller.setHook(address(0xBEEF));
        assertEq(controller.hook(), address(0xBEEF));
    }

    function testSetHookUnauthorized() public {
        vm.prank(address(0xA11CE));
        vm.expectRevert(YieldDistributionController.Unauthorized.selector);
        controller.setHook(address(1));
    }

    function testSetPoolConfigAndGet() public {
        YieldDistributionController.PoolConfig memory cfg = _defaultConfig();
        controller.setPoolConfig(poolId, cfg);

        YieldDistributionController.PoolConfig memory stored = controller.getPoolConfig(poolId);
        assertEq(stored.rebasingToken, cfg.rebasingToken);
        assertEq(stored.maxAmountIn, cfg.maxAmountIn);
    }

    function testSetPoolConfigInvalids() public {
        YieldDistributionController.PoolConfig memory cfg = _defaultConfig();

        cfg.rebasingToken = address(0);
        vm.expectRevert(YieldDistributionController.InvalidConfig.selector);
        controller.setPoolConfig(poolId, cfg);

        cfg = _defaultConfig();
        cfg.yieldSplitBps = 10_001;
        vm.expectRevert(YieldDistributionController.InvalidConfig.selector);
        controller.setPoolConfig(poolId, cfg);

        cfg = _defaultConfig();
        cfg.cooldownMaxAmountIn = cfg.maxAmountIn + 1;
        vm.expectRevert(YieldDistributionController.InvalidConfig.selector);
        controller.setPoolConfig(poolId, cfg);

        cfg = _defaultConfig();
        cfg.cooldownMaxImpactBps = cfg.maxImpactBps + 1;
        vm.expectRevert(YieldDistributionController.InvalidConfig.selector);
        controller.setPoolConfig(poolId, cfg);
    }

    function testRecordYieldSplit() public {
        controller.setHook(address(this));
        controller.setPoolConfig(poolId, _defaultConfig());

        (uint256 yieldDeltaRaw, uint256 distributedRaw) = controller.recordYieldDelta(poolId, 1e18, 1.1e18, 1_000 ether);

        assertEq(yieldDeltaRaw, 100 ether);
        assertEq(distributedRaw, 20 ether);

        YieldDistributionController.PoolAccounting memory accounting = controller.getPoolAccounting(poolId);
        assertEq(accounting.cumulativeYieldRaw, 100 ether);
        assertEq(accounting.cumulativeDistributedRaw, 20 ether);
        assertEq(accounting.lastObservedIndex, 1.1e18);
    }

    function testRecordYieldNeutral() public {
        YieldDistributionController.PoolConfig memory cfg = _defaultConfig();
        cfg.distributionMode = YieldDistributionController.DistributionMode.Neutral;

        controller.setHook(address(this));
        controller.setPoolConfig(poolId, cfg);

        (uint256 yieldDeltaRaw, uint256 distributedRaw) = controller.recordYieldDelta(poolId, 1e18, 1.1e18, 500 ether);

        assertEq(yieldDeltaRaw, 50 ether);
        assertEq(distributedRaw, 0);
    }

    function testRecordYieldUnauthorized() public {
        controller.setPoolConfig(poolId, _defaultConfig());

        vm.expectRevert(YieldDistributionController.Unauthorized.selector);
        controller.recordYieldDelta(poolId, 1e18, 1.1e18, 100 ether);
    }

    function testRecordYieldRevertsWhenPoolDisabled() public {
        controller.setHook(address(this));

        vm.expectRevert(YieldDistributionController.InvalidConfig.selector);
        controller.recordYieldDelta(poolId, 1e18, 1.1e18, 100 ether);
    }

    function testRecordYieldNoIncreaseProducesZeroDelta() public {
        controller.setHook(address(this));
        controller.setPoolConfig(poolId, _defaultConfig());

        (uint256 yieldDeltaRawA, uint256 distributedRawA) = controller.recordYieldDelta(poolId, 0, 1.1e18, 1_000 ether);
        assertEq(yieldDeltaRawA, 0);
        assertEq(distributedRawA, 0);

        (uint256 yieldDeltaRawB, uint256 distributedRawB) =
            controller.recordYieldDelta(poolId, 1.1e18, 1.1e18, 1_000 ether);
        assertEq(yieldDeltaRawB, 0);
        assertEq(distributedRawB, 0);
    }

    function _defaultConfig() internal pure returns (YieldDistributionController.PoolConfig memory) {
        return YieldDistributionController.PoolConfig({
            enabled: true,
            rebasingToken: address(0x1234),
            rebasingTokenIsCurrency0: true,
            maxIndexDeltaBps: 600,
            yieldSplitBps: 2_000,
            distributionMode: YieldDistributionController.DistributionMode.Split,
            maxAmountIn: 5 ether,
            cooldownMaxAmountIn: 0.5 ether,
            maxImpactBps: 100,
            cooldownMaxImpactBps: 50,
            cooldownSeconds: 30,
            hysteresisSeconds: 10
        });
    }
}
