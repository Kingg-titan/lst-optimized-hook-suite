# Security Notes

## Primary Attack Vectors
- rebase sniping before/after index updates
- dishonest rebasing-token interface
- DoS from excessively strict guardrails
- rounding-edge attacks
- config/admin abuse

## Mitigations
- `onlyPoolManager` callback restriction
- monotonic + max-delta index checks
- cooldown guardrails with bounded parameters
- explicit owner-only config operations
- comprehensive test coverage across edge/fuzz paths

## Residual Risk
This system improves fairness and resilience but is not attack-proof.
