// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library RebaseAccountingModule {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    error InvalidIndex();
    error IndexMustBeMonotonic(uint256 previousIndex, uint256 nextIndex);
    error IndexDeltaTooLarge(uint256 deltaBps, uint256 maxDeltaBps);

    struct PoolIndexState {
        uint256 lastIndex;
        uint40 lastIndexUpdate;
    }

    function normalizeDown(uint256 rawAmount, uint256 index_) internal pure returns (uint256) {
        if (index_ == 0) revert InvalidIndex();
        return (rawAmount * WAD) / index_;
    }

    function normalizeUp(uint256 rawAmount, uint256 index_) internal pure returns (uint256) {
        if (index_ == 0) revert InvalidIndex();
        if (rawAmount == 0) return 0;
        return ((rawAmount * WAD) + index_ - 1) / index_;
    }

    function denormalizeDown(uint256 normalizedAmount, uint256 index_) internal pure returns (uint256) {
        return (normalizedAmount * index_) / WAD;
    }

    function denormalizeUp(uint256 normalizedAmount, uint256 index_) internal pure returns (uint256) {
        if (normalizedAmount == 0) return 0;
        return ((normalizedAmount * index_) + WAD - 1) / WAD;
    }

    function detectAndUpdateIndex(PoolIndexState storage state, uint256 nextIndex, uint256 maxDeltaBps)
        internal
        returns (bool changed, uint256 previousIndex, uint256 deltaBps)
    {
        if (nextIndex == 0) revert InvalidIndex();

        previousIndex = state.lastIndex;
        if (previousIndex == 0) {
            state.lastIndex = nextIndex;
            state.lastIndexUpdate = uint40(block.timestamp);
            return (true, 0, 0);
        }

        if (nextIndex < previousIndex) revert IndexMustBeMonotonic(previousIndex, nextIndex);
        if (nextIndex == previousIndex) return (false, previousIndex, 0);

        unchecked {
            deltaBps = ((nextIndex - previousIndex) * BPS_DENOMINATOR) / previousIndex;
        }

        if (maxDeltaBps > 0 && deltaBps > maxDeltaBps) {
            revert IndexDeltaTooLarge(deltaBps, maxDeltaBps);
        }

        state.lastIndex = nextIndex;
        state.lastIndexUpdate = uint40(block.timestamp);
        changed = true;
    }
}
