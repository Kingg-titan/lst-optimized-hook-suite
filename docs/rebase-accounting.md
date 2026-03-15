# Rebase Accounting

## Units
- raw token units: ERC20 amount
- normalized units: raw converted via index (WAD)

## Conversions
- `normalizeDown(raw, index)`
- `normalizeUp(raw, index)`
- `denormalizeDown(norm, index)`
- `denormalizeUp(norm, index)`

## Invariants
- no synthetic value creation from rounding-down path
- index must be non-zero and monotonic
- index delta bounded by config (`maxIndexDeltaBps`)
