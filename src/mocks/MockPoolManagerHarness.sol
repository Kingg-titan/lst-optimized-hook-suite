// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

contract MockPoolManagerHarness {
    bytes32 internal constant POOLS_SLOT = bytes32(uint256(6));

    mapping(bytes32 => bytes32) internal slots;

    event BeforeSwapInvoked(address indexed hook, address indexed sender, bool ok, bytes data);
    event AfterSwapInvoked(address indexed hook, address indexed sender, bool ok, bytes data);

    function setRawSlot(bytes32 slot, bytes32 value) external {
        slots[slot] = value;
    }

    function setSlot0(PoolId poolId, uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee) external {
        bytes32 stateSlot = keccak256(abi.encodePacked(PoolId.unwrap(poolId), POOLS_SLOT));

        uint24 tickBits = uint24(uint256(int256(tick)));
        uint256 packed = uint256(sqrtPriceX96) | (uint256(tickBits) << 160) | (uint256(protocolFee) << 184)
            | (uint256(lpFee) << 208);

        slots[stateSlot] = bytes32(packed);
    }

    function callBeforeSwap(address hook, address sender, PoolKey calldata key, SwapParams calldata params)
        external
        returns (bool ok, bytes memory data)
    {
        (bool success, bytes memory result) =
            hook.call(abi.encodeCall(IHooks.beforeSwap, (sender, key, params, bytes(""))));

        if (success) {
            (bytes4 selector, BeforeSwapDelta delta, uint24 lpFeeOverride) =
                abi.decode(result, (bytes4, BeforeSwapDelta, uint24));
            ok = true;
            data = abi.encode(selector, delta, lpFeeOverride);
        } else {
            data = result;
        }

        emit BeforeSwapInvoked(hook, sender, ok, data);
    }

    function callAfterSwap(address hook, address sender, PoolKey calldata key, SwapParams calldata params)
        external
        returns (bool ok, bytes memory data)
    {
        (bool success, bytes memory result) =
            hook.call(abi.encodeCall(IHooks.afterSwap, (sender, key, params, BalanceDelta.wrap(0), bytes(""))));

        if (success) {
            (bytes4 selector, int128 unspecifiedDelta) = abi.decode(result, (bytes4, int128));
            ok = true;
            data = abi.encode(selector, unspecifiedDelta);
        } else {
            data = result;
        }

        emit AfterSwapInvoked(hook, sender, ok, data);
    }

    function extsload(bytes32 slot) external view returns (bytes32 value) {
        return slots[slot];
    }

    function extsload(bytes32 startSlot, uint256 nSlots) external view returns (bytes32[] memory values) {
        values = new bytes32[](nSlots);
        for (uint256 i = 0; i < nSlots; i++) {
            values[i] = slots[bytes32(uint256(startSlot) + i)];
        }
    }

    function extsload(bytes32[] calldata slots_) external view returns (bytes32[] memory values) {
        values = new bytes32[](slots_.length);
        for (uint256 i = 0; i < slots_.length; i++) {
            values[i] = slots[slots_[i]];
        }
    }
}
