# Deployment

## Local
```bash
make bootstrap
anvil
make demo-local
```

## Base Sepolia (Preferred)
```bash
cp .env.example .env
# set PRIVATE_KEY + RPC_URL_BASE_SEPOLIA
make demo-testnet
```

## Scripts
- deploy suite: `script/10_DeployLSTSuite.s.sol`
- configure pool: `script/11_ConfigPool.s.sol`

## Explorer Links
- Base Sepolia tx URL pattern: `https://sepolia.basescan.org/tx/<hash>`
- unsupported/unknown chain: `TBD` + raw hash
