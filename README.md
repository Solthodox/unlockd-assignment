## Convex Vaults

This solution implements the Convex protocol contracts.
## Bried overview

Convex is meant for two type of [Curve.fi](https://curve.fi/) users, allowing them to manage their positions easily and earn extra rewards in form of `CRV` tokens and Convex's `CVX` tokens:
- Liquidity providers
- CRV stakers

That's why this project has been set in 2 separate contracts:
 - CurveLPVault : for the liquidity providers
 - CRVStakingVault : for the CRV stakers



## Setup
Set `MAINNET_RPC_URL` environment variable in a `.env` file.

## Run tests
```bash
forge test
```
