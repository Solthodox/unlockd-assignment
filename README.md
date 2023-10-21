## Convex Vaults

This solution implements the `Convex`` protocol contracts.
## Bried overview

Convex is meant for two type of [Curve.fi](https://curve.fi/) users, allowing them to manage their positions easily and earn extra rewards in `CRV` and Convex's `CVX` tokens:
- Liquidity providers
- CRV stakers

That's why this project has been set in 2 separate contracts, that interact with Convex in different ways:

 - `CurveLPVault` : for the liquidity providers. Deposits liquidity tokens in `Booster`.
 - `CRVStakingVault` : for the CRV stakers. Permanently locks CRV tokens in Curve protocol to help Convex get a high voting power, through `CrvDepositor`. Users get `cvxCRV` tokens instead, that can be swap for real CRV at any time.

## Logic

The vaults are designed to supercharge user yields by compounding all rewards and distributing them in the underlying token, eliminating the need for users to claim various tokens from different sources. 

## Strategy

In every reward compounding, the vault claims all the earned CRV and CVX. Then performs the needed swaps in Curve to obtain more underlying tokens, and deposit them back again. 

## Functions

- `deposit`: deposit a amount of tokens in the vault.
- `withdraw` : burns vault shares to get the corresponding underlying tokens.
- `compoundRewards` : claims all the rewards and deposits them back again, to increment the underlying tokens for all the vault share owners.

## Getting started
Set `MAINNET_RPC_URL` environment variable in a `.env` file.

## Run tests
```bash
forge test
```
