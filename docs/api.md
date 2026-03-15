# API Reference

## LSTOptimizedHook
- `getHookPermissions()`
- `getGuardrailState(PoolId)`
- `constrainedSwapCount(PoolId)`

## YieldDistributionController
- `setHook(address)`
- `setPoolConfig(PoolId, PoolConfig)`
- `getPoolConfig(PoolId)`
- `getPoolAccounting(PoolId)`
- `recordYieldDelta(PoolId, prev, next, normalizedReserve)`

## MockRebasingLST
- `index()`
- `rebaseByBps(uint16)`
- `setIndex(uint256)`
- `mint(address,uint256)`
