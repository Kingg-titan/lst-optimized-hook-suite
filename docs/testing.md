# Testing

## Coverage Areas
- unit math for normalization and index checks
- guardrail edge conditions (amount/tick/cooldown)
- hook integration with real v4 pool manager flows
- fuzz scenarios for accounting and guardrail validity

## Commands
```bash
forge test
forge coverage --report summary
```
