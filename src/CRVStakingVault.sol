// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IBooster} from "./interfaces/IBooster.sol";
import {IRewards} from "./interfaces/IRewards.sol";
import {ICrvDepositor} from "./interfaces/ICrvDepositor.sol";
import {ICurvePool} from "./interfaces/ICurvePool.sol";

/// @notice implements the Convex functions for CRV stakers
contract CRVStakingVault is ERC20 {
    error CRVStakingVault__Deposit_AmountIsZero();
    error CRVStakingVault__Withdraw_CouldNotWithdraw();
    error CRVStakingVault__Compound_ClaimNotWorking();

    event Deposit(address indexed depositor, uint256 indexed amountUnderlying);
    event Withdraw(
        address indexed withdrawer, uint256 indexed shares, uint256 indexed amountUnderlying
    );

    using SafeTransferLib for address;

    /// @notice Convex's CRV representation token
    address constant CVXCRV = 0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7;

    /// @notice Rewards contract for CVXCRV
    address constant CVXCRV_REWARDER = 0x3Fe65692bfCD0e6CF84cB1E7d24108E434A7587e;

    /// @notice Pool used to exchange CVXCRV for the underlying CRV
    address constant CVXCRV_CRV_POOL = 0x971add32Ea87f10bD192671630be3BE8A11b8623;

    /// @notice Curve CRV token
    address public constant UNDERLYNG_ASSET = 0xD533a949740bb3306d119CC777fa900bA034cd52;

    /// @notice Convex main deposit contract
    address constant CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;

    // address del crv staking
    address constant REWARDER = 0x0A760466E1B4621579a82a39CB56Dda2F4E70f03;

    /// @notice Convex helper contract to deposit Crv
    address constant CONVEX_CRV_DEPOSITOR = 0x8014595F2AB54cD7c604B00E9fb932176fDc86Ae;

    function _deposit(uint256 amount) internal {
        UNDERLYNG_ASSET.safeApprove(CONVEX_CRV_DEPOSITOR, amount);
        // deposit locking the CRV permanently to get higher yield
        ICrvDepositor(CONVEX_CRV_DEPOSITOR).deposit(amount, true, CVXCRV_REWARDER);
    }

    /// @notice Deposit and permanently stake a amount of CRV token in Convex
    function deposit(uint256 amount) external returns (uint256 shares) {
        if (amount == 0) revert CRVStakingVault__Deposit_AmountIsZero();
        UNDERLYNG_ASSET.safeTransferFrom(msg.sender, address(this), amount);
        _deposit(amount);
        _mint(msg.sender, shares = amount);
        emit Deposit(msg.sender, shares);
    }

    /// @notice Withdraw the underlying balance either as cvxCRV or as CRV
    /// @param unwrap true to get CRV
    /// @notice the unwrap option causes slippage in the final amount
    function withdraw(uint256 amount, bool unwrap) external returns (uint256 amountOut) {
        uint256 cvxCRVAmount = _calculateUnderlyingBalance(amount);
        _burn(msg.sender, amount);
        if (!IRewards(CVXCRV_REWARDER).withdraw(cvxCRVAmount, false)) {
            revert CRVStakingVault__Withdraw_CouldNotWithdraw();
        }
        if (unwrap) {
            CVXCRV.safeApprove(CVXCRV_CRV_POOL, cvxCRVAmount);
            amountOut = ICurvePool(CVXCRV_CRV_POOL).exchange(1, 0, cvxCRVAmount, 0);
            UNDERLYNG_ASSET.safeTransfer(msg.sender, amountOut);
        } else {
            CVXCRV.safeTransfer(msg.sender, amountOut = cvxCRVAmount);
        }

        emit Withdraw(msg.sender, amount, amountOut);
    }

    function balanceOfUnderlying(address account) external view returns (uint256) {
        return _calculateUnderlyingBalance(balanceOf(account));
    }

    function _calculateUnderlyingBalance(uint256 balance) private view returns (uint256) {
        return CVXCRV_REWARDER.balanceOf(address(this)) * balance / totalSupply();
    }

    /// @notice reinvests the crv rewards to increase the position in the underlying token
    function compoundRewards() external returns (bool) {
        if (!IRewards(CVXCRV_REWARDER).getReward(address(this), false)) {
            revert CRVStakingVault__Compound_ClaimNotWorking();
        }
        uint256 crvBalance = UNDERLYNG_ASSET.balanceOf(address(this));
        if (crvBalance == 0) return false;
        _deposit(crvBalance);
        return true;
    }

    function previewUnwrap(uint256 amount) public view returns (uint256) {
        return ICurvePool(CVXCRV_CRV_POOL).get_dy(1, 0, amount);
    }

    /*///////////////////////////////////////////////////////////////
                            FUNCTION OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function name() public pure override returns (string memory) {
        return "Curve DAO Token Vault";
    }

    function symbol() public pure override returns (string memory) {
        return "CRVv";
    }
}
