// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

contract YieldDistributionController {
    enum DistributionMode {
        Neutral,
        Split
    }

    struct PoolConfig {
        bool enabled;
        address rebasingToken;
        bool rebasingTokenIsCurrency0;
        uint16 maxIndexDeltaBps;
        uint16 yieldSplitBps;
        DistributionMode distributionMode;
        uint256 maxAmountIn;
        uint256 cooldownMaxAmountIn;
        uint16 maxImpactBps;
        uint16 cooldownMaxImpactBps;
        uint40 cooldownSeconds;
        uint40 hysteresisSeconds;
    }

    struct PoolAccounting {
        uint256 lastYieldDeltaRaw;
        uint256 cumulativeYieldRaw;
        uint256 cumulativeDistributedRaw;
        uint256 lastObservedIndex;
    }

    error Unauthorized();
    error InvalidConfig();

    event HookUpdated(address indexed previousHook, address indexed nextHook);
    event PoolConfigUpdated(bytes32 indexed poolId, PoolConfig config);
    event YieldRecorded(
        bytes32 indexed poolId,
        uint256 previousIndex,
        uint256 nextIndex,
        uint256 normalizedReserve,
        uint256 yieldDeltaRaw,
        uint256 distributedRaw
    );

    address public immutable owner;
    address public hook;

    mapping(bytes32 => PoolConfig) private poolConfigs;
    mapping(bytes32 => PoolAccounting) private poolAccounting;

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyHook() {
        if (msg.sender != hook) revert Unauthorized();
        _;
    }

    constructor(address owner_) {
        owner = owner_;
    }

    function setHook(address nextHook) external onlyOwner {
        emit HookUpdated(hook, nextHook);
        hook = nextHook;
    }

    function setPoolConfig(PoolId poolId, PoolConfig calldata config) external onlyOwner {
        if (config.rebasingToken == address(0)) revert InvalidConfig();
        if (config.yieldSplitBps > 10_000) revert InvalidConfig();
        if (config.cooldownMaxAmountIn > config.maxAmountIn && config.maxAmountIn != 0) revert InvalidConfig();
        if (config.cooldownMaxImpactBps > config.maxImpactBps && config.maxImpactBps != 0) revert InvalidConfig();

        bytes32 id = PoolId.unwrap(poolId);
        poolConfigs[id] = config;
        emit PoolConfigUpdated(id, config);
    }

    function getPoolConfig(PoolId poolId) external view returns (PoolConfig memory) {
        return poolConfigs[PoolId.unwrap(poolId)];
    }

    function getPoolAccounting(PoolId poolId) external view returns (PoolAccounting memory) {
        return poolAccounting[PoolId.unwrap(poolId)];
    }

    function recordYieldDelta(PoolId poolId, uint256 previousIndex, uint256 nextIndex, uint256 normalizedReserve)
        external
        onlyHook
        returns (uint256 yieldDeltaRaw, uint256 distributedRaw)
    {
        bytes32 id = PoolId.unwrap(poolId);
        PoolConfig memory cfg = poolConfigs[id];
        if (!cfg.enabled) revert InvalidConfig();

        if (previousIndex > 0 && nextIndex > previousIndex) {
            yieldDeltaRaw = (normalizedReserve * (nextIndex - previousIndex)) / 1e18;
        }

        if (yieldDeltaRaw > 0 && cfg.distributionMode == DistributionMode.Split && cfg.yieldSplitBps > 0) {
            distributedRaw = (yieldDeltaRaw * cfg.yieldSplitBps) / 10_000;
        }

        PoolAccounting storage accounting = poolAccounting[id];
        accounting.lastYieldDeltaRaw = yieldDeltaRaw;
        accounting.cumulativeYieldRaw += yieldDeltaRaw;
        accounting.cumulativeDistributedRaw += distributedRaw;
        accounting.lastObservedIndex = nextIndex;

        emit YieldRecorded(id, previousIndex, nextIndex, normalizedReserve, yieldDeltaRaw, distributedRaw);
    }
}
