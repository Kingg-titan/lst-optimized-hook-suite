# Contributing

## Prerequisites
- Foundry (stable)
- Node.js 20+
- npm 10+

## Setup
```bash
make bootstrap
npm install --workspaces
forge build
forge test
```

## Development Rules
- keep dependencies pinned and reproducible
- preserve deterministic logic in swap-time execution
- add/extend tests for every behavior change
- avoid introducing external automation dependencies

## Required Checks
```bash
forge test
forge coverage --report summary
npm run --workspace frontend build
```

## Commit Count Validation
```bash
bash scripts/verify_commits.sh <expected_count>
```
