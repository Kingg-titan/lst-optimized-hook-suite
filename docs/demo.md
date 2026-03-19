# Demo Flow

This project ships with a phased testnet + local proof script:

```bash
make demo-testnet
```

It executes the following phases with explicit logs:

1. `phase 0/5 - preflight`
- resolves RPC, chain id, owner, pool manager
- prints explorer tx base

2. `phase 1/5 - deployment resolution`
- if deployment addresses are missing in `.env`, deploys contracts
- if addresses already exist, reuses them
- persists addresses into `.env`

3. `phase 2/5 - controller/pool config`
- calls `script/11_ConfigPool.s.sol:ConfigPool`
- prints tx hash + explorer URL
- prints computed `poolId`

4. `phase 3/6 - user perspective`
- reads rebasing token index before rebase
- sends `rebaseByBps(uint16)` transaction
- prints tx hash + explorer URL
- reads index after rebase

5. `phase 4/6 - onchain lifecycle tx proof`
- runs `script/12_RunLifecycleTxDemo.s.sol`
- prints tx hashes + explorer URLs for:
  - normal swap path
  - rebase detection
  - cooldown-constrained swap
  - oversized blocked attempt
  - post-cooldown allowed swap
  - deterministic yield accounting checkpoint

6. `phase 5/6 - local deterministic proof`
- runs `forge test --match-test testDemoLifecycleSummary -vv`
- prints deterministic proof logs:
  - normal-trade path (no constraints)
  - rebase-triggered cooldown
  - oversized swap blocked in cooldown
  - post-cooldown swap allowed
  - yield accounting deltas

7. `phase 6/6 - summary`
- prints effective deployed addresses used in the run

## Additional demo entry points
- `make demo-local` runs the lifecycle proof test only
- `make demo-rebase` runs the focused rebase/cooldown test
- `make demo-all` runs bootstrap/build/test + local/rebase/testnet demos
