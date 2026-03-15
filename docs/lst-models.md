# LST Models

## Model A: Rebasing Index Token (Implemented Mock)
- `index()` in WAD (`1e18` scale)
- bounded monotonic rebase updates
- compatible ERC20 transfer behavior for pool settlement safety

## Model B: Non-Rebasing Reference Token
- standard ERC20 balances
- independent exchange-rate variable for comparative docs/demo

## Assumptions
- index is monotonic in normal operation
- index source is honest for configured token
