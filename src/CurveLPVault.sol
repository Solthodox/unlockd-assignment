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
    /*///////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/
    error CurveLPVault__Deposit_AmountIsZero();
    error CurveLPVault__Deposit_CouldNotDeposit();
    error CurveLPVault__Withdraw_CouldNotWithdraw();
    error CurveLPVault__Compound_ClaimNotWorking();

    /*///////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/
    event Deposit(address indexed depositor, uint256 indexed amountUnderlying);
    event Withdraw(
        address indexed withdrawer, uint256 indexed shares, uint256 indexed amountUnderlying
    );
    event CompoundRewards(uint256 earned, uint256 indexed timestamp);

    using SafeTransferLib for address;

    /*///////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Convex token
    address constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;

    /// @notice Curve DAO Token
    address constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;

    /// @notice ETH/CVX curve pool
    address constant ETH_CVX = 0xB576491F1E6e5E62f1d8F26062Ee822B40B0E0d4;

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


    /*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAW LOGIC
    //////////////////////////////////////////////////////////////*/

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

    /*///////////////////////////////////////////////////////////////
                        COMPOUND/CALCULATIONS
    //////////////////////////////////////////////////////////////*/

    /// @return the underlying tokens(initial deposit + yield) of a user
    function balanceOfUnderlying(address account) external view returns (uint256) {
        return _calculateUnderlyingBalance(balanceOf(account));
    }
    
    /// @return the total underlying tokens held by the vault
    function totalAssets() public view virtual returns (uint256) {
        return POOL_REWARDER.balanceOf(address(this));
    }

    function _calculateUnderlyingBalance(uint256 balance) private view returns (uint256) {
        return POOL_REWARDER.balanceOf(address(this)) * balance / totalSupply();
    }

    /// @notice reinvests the CRV and CVX rewards to increase the position in the underlying token
    /// @return true if any rewards were compounded
    function compoundRewards() external returns (bool) {
        // claim crv and cvx rewards from stake contract
        if (!IRewards(POOL_REWARDER).getReward(address(this), false)) {
            revert CurveLPVault__Compound_ClaimNotWorking();
        }

        uint256 crvBalance = CRV.balanceOf(address(this));
        uint256 cvxBalance = CVX.balanceOf(address(this));
        if (crvBalance == 0 && cvxBalance == 0) return false;

        uint256 amountETH;
        if (cvxBalance > 0) {
            // exchange CVX for ETH
            CVX.safeApprove(ETH_CVX, cvxBalance);
            amountETH = ICurvePool(ETH_CVX).exchange(1, 0, cvxBalance, 0, true);
        }

        if (crvBalance > 0) {
            CRV.safeApprove(TRICRV, crvBalance);
            // exchange CRV for ETH
            amountETH += ICurvePool(TRICRV).exchange_underlying(2, 1, crvBalance, 0, address(this));
        }
        ICurvePool underlyingPool = ICurvePool(UNDERLYING_POOL);
        uint256 exchangeAmountETH = amountETH / 2;
        // exchange half of eth for seth
        uint256 amountSETH = underlyingPool.exchange{value: exchangeAmountETH}(0, 1, exchangeAmountETH, 0);
        SETH.safeApprove(UNDERLYING_POOL, amountSETH);
        // add liquidity to mint more LP tokens
        uint256 mintedLiquidity = underlyingPool.add_liquidity{value: amountETH - exchangeAmountETH}(
            [amountETH - exchangeAmountETH, amountSETH], 0
        );
        UNDERLYNG_ASSET.safeApprove(CONVEX_BOOSTER, mintedLiquidity);
        // deposit the LP tokens in the Booster again
        if (!IBooster(CONVEX_BOOSTER).deposit(POOL_ID, mintedLiquidity, true)) {
            revert CurveLPVault__Deposit_CouldNotDeposit();
        }
        emit CompoundRewards(mintedLiquidity, block.timestamp);
        return true;
    }

    receive() external payable {}

    /*///////////////////////////////////////////////////////////////
                            FUNCTION OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function name() public pure override returns (string memory) {
        return "Curve.fi ETH/stETH Vault";
    }

    function symbol() public pure override returns (string memory) {
        return "steCRVv";
    }

}
