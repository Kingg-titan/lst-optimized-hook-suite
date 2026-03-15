# Security Policy

## Supported Scope
- Solidity contracts under `src/`
- deployment/config scripts under `script/` and `scripts/`
- frontend ABI interactions under `frontend/`

## Reporting
Report issues privately to project maintainers before public disclosure.

## Threat Model Highlights
- rebase sniping around index updates
- malicious or dishonest rebasing token interface
- griefing via overly tight guardrails
- rounding-edge exploitation
- admin misconfiguration risk

## Mitigations
- `onlyPoolManager` hook entrypoint enforcement
- bounded `maxIndexDeltaBps`
- cooldown regime constraints (`maxAmountIn`, `maxImpactBps`)
- deterministic conversion helpers with explicit rounding direction
- owner-only config updates in controller

## Residual Risks
- guardrails reduce, but do not eliminate, toxic flow/MEV
- admin key compromise can reconfigure pool behavior
- simplistic tick movement approximation may be conservative
