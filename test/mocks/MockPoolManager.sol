// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

contract MockPoolManager {
    bytes32 internal constant POOLS_SLOT = bytes32(uint256(6));

    mapping(bytes32 => bytes32) internal slots;

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
