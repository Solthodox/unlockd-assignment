// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IBooster} from "./interfaces/IBooster.sol";
import {ICrvDepositor} from "./interfaces/ICrvDepositor.sol";
import {IRewards} from "./interfaces/IRewards.sol";
import {ICurvePool} from "./interfaces/ICurvePool.sol";

/// @notice implements the Convex functions for Curve liquidity providers
/// @notice best approach would be ERC4626 but since you asked for {deposit} and {withdraw} functions only:
contract CurveLPVault is ERC20 {
    /// ERRORS
    error CurveLPVault__Deposit_AmountIsZero();
    error CurveLPVault__Deposit_CouldNotDeposit();
    error CurveLPVault__Withdraw_CouldNotWithdraw();
    error CurveLPVault__Compound_ClaimNotWorking();

    /// EVENTS
    event Deposit(address indexed depositor, uint256 indexed amountUnderlying);
    event Withdraw(
        address indexed withdrawer, uint256 indexed shares, uint256 indexed amountUnderlying
    );

    using SafeTransferLib for address;

    /// @notice Curve DAO Token
    address constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;

    /// @notice Lido sETH token
    address constant SETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    /// @notice TriCRV pool used to exchange crv rewards for eth
    address constant TRICRV = 0x4eBdF703948ddCEA3B11f675B4D1Fba9d2414A14;

    /// @notice ETH/sETH pool
    address constant UNDERLYING_POOL = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;

    /// @notice Curve Curve.fi ETH/stETH pool LP token(steCRV)
    address public constant UNDERLYNG_ASSET = 0x06325440D014e39736583c165C2963BA99fAf14E;

    /// @notice Convex main deposit contract
    address constant CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;

    /// @notice Rewards contract for this LP token
    address constant POOL_REWARDER = 0x0A760466E1B4621579a82a39CB56Dda2F4E70f03;

    /// @notice The token that represents position in the pool in Convex
    address constant CONVEX_POOL_TOKEN = 0x9518c9063eB0262D791f38d8d6Eb0aca33c63ed0;

    /// @notice The id of the pool in Booster
    uint256 constant POOL_ID = 25;

    function _deposit(uint256 amount) internal {
        UNDERLYNG_ASSET.safeApprove(CONVEX_BOOSTER, amount);
        // we set staking to true to receive boosted crv rewards
        if (!IBooster(CONVEX_BOOSTER).deposit(POOL_ID, amount, true)) {
            revert CurveLPVault__Deposit_CouldNotDeposit();
        }
    }

    /// @notice Deposit steCRV LP tokens in Convex
    /// @param amount amount of underlying asset tokens to deposit
    function deposit(uint256 amount) external returns (uint256 shares) {
        if (amount == 0) revert CurveLPVault__Deposit_AmountIsZero();
        UNDERLYNG_ASSET.safeTransferFrom(msg.sender, address(this), amount);
        _deposit(amount);
        // mint shares
        _mint(msg.sender, shares = amount);
        emit Deposit(msg.sender, amount);
    }

    /// @notice withdraws the underlying balance pro-rata to the shares
    /// @param amount the amount of vault shares to burn
    function withdraw(uint256 amount) external returns (uint256 amountUnderlying) {
        // calculate lp token amount
        amountUnderlying = _calculateUnderlyingBalance(amount);
        // burn shares
        _burn(msg.sender, amount);
        // withdraw lp tokens from stake contract
        if (!IRewards(POOL_REWARDER).withdrawAndUnwrap(amountUnderlying, false)) {
            revert CurveLPVault__Withdraw_CouldNotWithdraw();
        }
        UNDERLYNG_ASSET.safeTransfer(msg.sender, amountUnderlying);
        emit Withdraw(msg.sender, amount, amountUnderlying);
    }

    function balanceOfUnderlying(address account) external view returns (uint256) {
        return _calculateUnderlyingBalance(balanceOf(account));
    }

    function totalAssets() public view virtual returns (uint256){
        return POOL_REWARDER.balanceOf(address(this));
    }


    function _calculateUnderlyingBalance(uint256 balance) private view returns (uint256) {
        return POOL_REWARDER.balanceOf(address(this)) * balance / totalSupply();
    }

    /// @notice reinvests the crv rewards to increase the position in the underlying token
    function compoundRewards() external returns (bool) {
        // claim crv rewards from stake contract
        if (!IRewards(POOL_REWARDER).getReward(address(this), false)) {
            revert CurveLPVault__Compound_ClaimNotWorking();
        }
        uint256 crvBalance = CRV.balanceOf(address(this));
        if (crvBalance == 0) return false;
        CRV.safeApprove(TRICRV, crvBalance);
        uint256 amountETH =
            ICurvePool(TRICRV).exchange_underlying(2, 1, crvBalance, 0, address(this));
        // get ETH
        ICurvePool underlyingPool = ICurvePool(UNDERLYING_POOL);
        uint256 swapAmountETH = amountETH;
        // get SETH
        uint256 amountSETH = underlyingPool.exchange{value: swapAmountETH}(0, 1, swapAmountETH, 0);
        SETH.safeApprove(UNDERLYING_POOL, amountSETH);
        // add liquidity to mint more LP tokens
        uint256 mintedLiquidity =
            underlyingPool.add_liquidity([amountETH - swapAmountETH, amountSETH], 0);
        UNDERLYNG_ASSET.safeApprove(CONVEX_BOOSTER, mintedLiquidity);
        // deposit the LP tokens in the Booster again
        if (!IBooster(CONVEX_BOOSTER).deposit(POOL_ID, mintedLiquidity, true)) {
            revert CurveLPVault__Deposit_CouldNotDeposit();
        }
        return true;
    }

    function name() public pure override returns (string memory) {
        return "Curve.fi ETH/stETH Vault";
    }

    function symbol() public pure override returns (string memory) {
        return "steCRVv";
    }

    receive() external payable {}
}
