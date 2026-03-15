# Guardrails

## Regimes
- Normal regime
  - `maxAmountIn`
  - `maxImpactBps`
- Cooldown regime (index-change triggered)
  - `cooldownMaxAmountIn`
  - `cooldownMaxImpactBps`

## Determinism
- no oracle dependency
- tick movement checked using pool state snapshots
- cooldown timing uses block timestamp and explicit duration
