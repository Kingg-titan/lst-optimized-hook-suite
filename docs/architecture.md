# Architecture

## Components
- `LSTOptimizedHook`: swap lifecycle entry point (`beforeSwap`/`afterSwap`)
- `RebaseAccountingModule`: normalized math + index safety checks
- `PricingGuardrails`: deterministic limits for amount and tick movement
- `YieldDistributionController`: pool config + cumulative yield accounting
- `MockRebasingLST`: deterministic index model for demo/tests

## Interaction Diagram
```mermaid
flowchart LR
  FE[Frontend] --> H[Hook]
  FE --> C[Controller]
  H --> PM[PoolManager]
  H --> C
  H --> RAM[RebaseAccountingModule]
  H --> PG[PricingGuardrails]
  LST[index()] --> H
```
