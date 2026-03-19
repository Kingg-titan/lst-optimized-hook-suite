# Deployment

## Local
```bash
make bootstrap
anvil
make demo-local
```

## Unichain Sepolia
```bash
cp .env.example .env
# set PRIVATE_KEY / SEPOLIA_PRIVATE_KEY + RPC_URL_BASE_SEPOLIA
make demo-testnet
```

## Scripts
- deploy suite: `script/10_DeployLSTSuite.s.sol`
- configure pool: `script/11_ConfigPool.s.sol`

## Deployed Addresses (Unichain Sepolia, chainId 1301)
- `YieldDistributionController`: `0xBdb3472D1D3eF34662e44c3142EfC0366877ca7f`
- `LSTOptimizedHook`: `0xd6DF2976E510312F782C91146c0387d6085880c0`
- `MockRebasingLST`: `0x6744af6f637887495E261Ec0f14c9bF9F10cA1B9`
- `MockNonRebasingLST`: `0x5793351da4b69071fe012213fb1e9f7465C519F9`

## Explorer Links
- explorer tx pattern: `https://sepolia.uniscan.xyz/tx/<hash>`
- example rebase tx:
  - `0xd90755437d813c8d0560661de0a0778282f42a5c0fedefb452f534e4f9bbbcbb`
  - `https://sepolia.uniscan.xyz/tx/0xd90755437d813c8d0560661de0a0778282f42a5c0fedefb452f534e4f9bbbcbb`
