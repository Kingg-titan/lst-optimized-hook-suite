// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

import {MockPoolManagerHarness} from "src/mocks/MockPoolManagerHarness.sol";

contract MockHookResponder {
    bool public revertBefore;
    bool public revertAfter;

    function setRevertBefore(bool value) external {
        revertBefore = value;
    }

    function setRevertAfter(bool value) external {
        revertAfter = value;
    }

    function beforeSwap(address, PoolKey calldata, SwapParams calldata, bytes calldata)
        external
        view
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        if (revertBefore) revert("before-fail");
        return (this.beforeSwap.selector, BeforeSwapDelta.wrap(0), 77);
    }

    function afterSwap(address, PoolKey calldata, SwapParams calldata, int256, bytes calldata)
        external
        view
        returns (bytes4, int128)
    {
        if (revertAfter) revert("after-fail");
        return (this.afterSwap.selector, int128(11));
    }
}

contract MockPoolManagerHarnessTest is Test {
    MockPoolManagerHarness internal harness;
    MockHookResponder internal hook;
    PoolKey internal key;
    SwapParams internal params;

    function setUp() external {
        harness = new MockPoolManagerHarness();
        hook = new MockHookResponder();

        Currency c0 = Currency.wrap(address(0x1111));
        Currency c1 = Currency.wrap(address(0x2222));
        key = PoolKey(c0, c1, 3000, 60, IHooks(address(hook)));
        params = SwapParams({zeroForOne: true, amountSpecified: -int256(1 ether), sqrtPriceLimitX96: 0});
    }

    function testSetRawSlotAndExtsloadSingle() external {
        bytes32 slot = bytes32(uint256(42));
        bytes32 value = keccak256("v1");
        harness.setRawSlot(slot, value);
        assertEq(harness.extsload(slot), value);
    }

    function testSetSlot0PacksExpectedValue() external {
        PoolId poolId = PoolId.wrap(bytes32(uint256(777)));
        uint160 sqrtPriceX96 = 123_456;
        int24 tick = -45;
        uint24 protocolFee = 7;
        uint24 lpFee = 3000;

        harness.setSlot0(poolId, sqrtPriceX96, tick, protocolFee, lpFee);

        bytes32 poolsSlot = bytes32(uint256(6));
        bytes32 stateSlot = keccak256(abi.encodePacked(PoolId.unwrap(poolId), poolsSlot));
        uint24 tickBits = uint24(uint256(int256(tick)));
        uint256 packed =
            uint256(sqrtPriceX96) | (uint256(tickBits) << 160) | (uint256(protocolFee) << 184) | (uint256(lpFee) << 208);

        assertEq(harness.extsload(stateSlot), bytes32(packed));
    }

    function testExtsloadRangeWithValues() external {
        bytes32 start = bytes32(uint256(100));
        harness.setRawSlot(start, bytes32(uint256(1)));
        harness.setRawSlot(bytes32(uint256(start) + 1), bytes32(uint256(2)));
        harness.setRawSlot(bytes32(uint256(start) + 2), bytes32(uint256(3)));

        bytes32[] memory values = harness.extsload(start, 3);
        assertEq(values.length, 3);
        assertEq(values[0], bytes32(uint256(1)));
        assertEq(values[1], bytes32(uint256(2)));
        assertEq(values[2], bytes32(uint256(3)));
    }

    function testExtsloadRangeWithZeroLength() external view {
        bytes32[] memory values = harness.extsload(bytes32(uint256(500)), 0);
        assertEq(values.length, 0);
    }

    function testExtsloadArrayWithValues() external {
        bytes32 slotA = bytes32(uint256(901));
        bytes32 slotB = bytes32(uint256(999));
        harness.setRawSlot(slotA, bytes32(uint256(11)));
        harness.setRawSlot(slotB, bytes32(uint256(22)));

        bytes32[] memory query = new bytes32[](2);
        query[0] = slotA;
        query[1] = slotB;
        bytes32[] memory values = harness.extsload(query);

        assertEq(values.length, 2);
        assertEq(values[0], bytes32(uint256(11)));
        assertEq(values[1], bytes32(uint256(22)));
    }

    function testExtsloadArrayWithZeroLength() external view {
        bytes32[] memory query = new bytes32[](0);
        bytes32[] memory values = harness.extsload(query);
        assertEq(values.length, 0);
    }

    function testCallBeforeSwapSuccess() external {
        (bool ok, bytes memory data) = harness.callBeforeSwap(address(hook), address(this), key, params);
        assertTrue(ok);
        (bytes4 selector, BeforeSwapDelta delta, uint24 lpFeeOverride) =
            abi.decode(data, (bytes4, BeforeSwapDelta, uint24));
        assertEq(selector, MockHookResponder.beforeSwap.selector);
        assertEq(BeforeSwapDelta.unwrap(delta), 0);
        assertEq(lpFeeOverride, 77);
    }

    function testCallBeforeSwapFailure() external {
        hook.setRevertBefore(true);
        (bool ok, bytes memory data) = harness.callBeforeSwap(address(hook), address(this), key, params);
        assertFalse(ok);
        assertGt(data.length, 4);
    }

    function testCallAfterSwapSuccess() external {
        (bool ok, bytes memory data) = harness.callAfterSwap(address(hook), address(this), key, params);
        assertTrue(ok);
        (bytes4 selector, int128 unspecifiedDelta) = abi.decode(data, (bytes4, int128));
        assertEq(selector, MockHookResponder.afterSwap.selector);
        assertEq(int256(unspecifiedDelta), 11);
    }

    function testCallAfterSwapFailure() external {
        hook.setRevertAfter(true);
        (bool ok, bytes memory data) = harness.callAfterSwap(address(hook), address(this), key, params);
        assertFalse(ok);
        assertGt(data.length, 4);
    }
}
