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
    /*///////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/
    error CRVStakingVault__Deposit_AmountIsZero();
    error CRVStakingVault__Withdraw_CouldNotWithdraw();
    error CRVStakingVault__Compound_ClaimNotWorking();

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

    /// @notice Convex's CRV representation token
    address constant CVXCRV = 0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7;

    /// @notice Convex troken
    address constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;

    /// @notice TriCRV pool used to exchange crv rewards for eth
    address constant TRICRV = 0x4eBdF703948ddCEA3B11f675B4D1Fba9d2414A14;

    /// @notice ETH/CVX pool used to exchange crv rewards for eth
    address constant ETH_CVX = 0xB576491F1E6e5E62f1d8F26062Ee822B40B0E0d4;

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


    /*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAW LOGIC
    //////////////////////////////////////////////////////////////*/
    
    function _deposit(uint256 amount) internal {
        UNDERLYNG_ASSET.safeApprove(CONVEX_CRV_DEPOSITOR, amount);
        // deposit locking the CRV permanently to get higher yield
        assembly {
            let ptr := mload(0x40) //cache the free memory pointer
            mstore(0x60,0x3Fe65692bfCD0e6CF84cB1E7d24108E434A7587e) // CVXCRV_REWARDER
            mstore(0x40, 1) // true
            mstore(0x20, amount) // amount
            mstore(0x0c,0x80ed71e4000000000000000000000000) // deposit(uint256,bool,address)

            if iszero(
                call(gas(), 0x8014595F2AB54cD7c604B00E9fb932176fDc86Ae, 0, 0x1c, 0x64, 0x00, 0x00)// function doesnt return anything
            ) {
                // if reverts 
                mstore(0x00, 0xe9d86c23) // store error `CRVStakingVault__Deposit_DepositFailed()`.
                revert(0x1c, 0x04) // revert with the error
            }
            mstore(0x60, 0) // Restore the zero slot to zero.
            mstore(0x40, ptr) // Restore the free memory pointer.
        }
        //ICrvDepositor(CONVEX_CRV_DEPOSITOR).deposit(amount, true, CVXCRV_REWARDER);
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

    /*///////////////////////////////////////////////////////////////
                        COMPOUND/CALCULATIONS
    //////////////////////////////////////////////////////////////*/

    /// @return the underlying tokens(initial deposit + yield) of a user
    /// @notice the amount is calculated in cvxCRV, exchanging them for CRV will cause slippage
    function balanceOfUnderlying(address account) external view returns (uint256) {
        return _calculateUnderlyingBalance(balanceOf(account));
    }

    /// @return the total underlying tokens held by the vault
    function totalAssets() public view virtual returns (uint256) {
        return CVXCRV_REWARDER.balanceOf(address(this));
    }

    function _calculateUnderlyingBalance(uint256 balance) private view returns (uint256) {
        return CVXCRV_REWARDER.balanceOf(address(this)) * balance / totalSupply();
    }

    /// @notice reinvests the CRV and CVX rewards to increase the position in the underlying token
    /// @return true if any rewards were compounded
    function compoundRewards() external returns (bool) {
        // claim crv and cvx rewards from stake contract
        if (!IRewards(CVXCRV_REWARDER).getReward(address(this), false)) {
            revert CRVStakingVault__Compound_ClaimNotWorking();
        }
        uint256 cvxBalance = CVX.balanceOf(address(this));
        uint256 crvBalance = UNDERLYNG_ASSET.balanceOf(address(this));
        if (crvBalance == 0 && cvxBalance == 0) return false;
        if (cvxBalance > 0) {
            // exchange CVX for CRV
            CVX.safeApprove(ETH_CVX, cvxBalance);
            uint256 ethAmount = ICurvePool(ETH_CVX).exchange(1, 0, cvxBalance, 0, true);
            crvBalance += ICurvePool(TRICRV).exchange_underlying{value: ethAmount}(
                1, 2, ethAmount, 0, address(this)
            );
        }
        _deposit(crvBalance);
        emit CompoundRewards(crvBalance , block.timestamp);
        return true;
    }
    /// @return the amount of CRV tokens in exchange of cvxCRV underlying tokens
    function previewUnwrap(uint256 amount) public view returns (uint256) {
        return ICurvePool(CVXCRV_CRV_POOL).get_dy(1, 0, amount);
    }
    
    receive() external payable {}

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
