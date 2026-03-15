# Demo Flow

## A) Normal Trading
1. deploy contracts
2. configure pool
3. execute swap with constant index

## B) Rebase Stress Window
1. call `rebaseByBps` on mock rebasing token
2. first swap after index change enters cooldown regime
3. oversized swap reverts under cooldown limits
4. post-cooldown swap succeeds under normal regime

## One-Command Demos
- `make demo-local`
- `make demo-rebase`
- `make demo-all`
