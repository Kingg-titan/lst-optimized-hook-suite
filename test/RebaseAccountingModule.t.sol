// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {RebaseAccountingModule} from "src/modules/RebaseAccountingModule.sol";

contract IndexHarness {
    using RebaseAccountingModule for RebaseAccountingModule.PoolIndexState;

    RebaseAccountingModule.PoolIndexState internal state;

    function detect(uint256 nextIndex, uint256 maxDeltaBps)
        external
        returns (bool changed, uint256 previousIndex, uint256 deltaBps)
    {
        return state.detectAndUpdateIndex(nextIndex, maxDeltaBps);
    }
}

contract RebaseAccountingModuleTest is Test {
    using RebaseAccountingModule for RebaseAccountingModule.PoolIndexState;

    RebaseAccountingModule.PoolIndexState internal state;
    IndexHarness internal harness;

    function setUp() public {
        harness = new IndexHarness();
    }

    function testNormalizeAndDenormalizeRoundTripDown() public pure {
        uint256 index_ = 1.12e18;
        uint256 raw = 1234.5678e18;

        uint256 normalized = RebaseAccountingModule.normalizeDown(raw, index_);
        uint256 recovered = RebaseAccountingModule.denormalizeDown(normalized, index_);

        assertLe(recovered, raw);
        assertLe(raw - recovered, 1);
    }

    function testDetectAndUpdateIndex() public {
        (bool changed0, uint256 previous0, uint256 delta0) = state.detectAndUpdateIndex(1e18, 500);
        assertTrue(changed0);
        assertEq(previous0, 0);
        assertEq(delta0, 0);

        (bool changed1, uint256 previous1, uint256 delta1) = state.detectAndUpdateIndex(1.02e18, 500);
        assertTrue(changed1);
        assertEq(previous1, 1e18);
        assertEq(delta1, 200);
    }

    function testDetectAndUpdateIndexRejectsLargeDelta() public {
        harness.detect(1e18, 300);
        vm.expectRevert();
        harness.detect(1.1e18, 300);
    }

    function testFuzzRoundTripSafety(uint128 rawAmount, uint128 index_) public pure {
        vm.assume(index_ > 0);

        uint256 normalized = RebaseAccountingModule.normalizeDown(rawAmount, index_);
        uint256 recovered = RebaseAccountingModule.denormalizeDown(normalized, index_);

        assertLe(recovered, rawAmount);
    }

    function testFuzzMonotonicIndexAssumption(uint128 a, uint128 b) public {
        uint256 initial = uint256(a) + 1e18;
        state.detectAndUpdateIndex(initial, 10_000);

        uint256 next = initial + uint256(b % 1000);
        (bool changed,,) = state.detectAndUpdateIndex(next, 10_000);

        if (next == initial) {
            assertTrue(!changed);
        } else {
            assertTrue(changed);
        }
    }
}
