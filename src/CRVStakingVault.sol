// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IBooster} from "./interfaces/IBooster.sol";
import {ICrvDepositor} from "./interfaces/ICrvDepositor.sol";

/// @notice best approach would be ERC4626 but since you asked for {deposit} and {withdraw} functions only:
contract CRVStakingVault is ERC20 {
    error CRVStakingVault__Deposit_AmountIsZero();

    event Deposit(address indexed depositor, uint256 indexed amount);

    using SafeTransferLib for address;

    /// @notice Curve CRV token
    address public constant UNDERLYNG_ASSET = 0xD533a949740bb3306d119CC777fa900bA034cd52;

    /// @notice Convex main deposit contract
    address public constant CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;

    /// @notice Convex helper contract to deposit Crv
    address public constant CONVEX_CRV_DEPOSITOR = 0x8014595F2AB54cD7c604B00E9fb932176fDc86Ae;

    /// @notice constant for scaling decimals from CRV amount to share amount
    uint256 constant PRECISION = 10 ** 12; // 30 -18

    function deposit(uint256 amount) external {
        if (amount == 0) revert CRVStakingVault__Deposit_AmountIsZero();
        UNDERLYNG_ASSET.safeTransferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount * PRECISION);
        UNDERLYNG_ASSET.safeApprove(CONVEX_CRV_DEPOSITOR, amount);
        // deposit locking the CRV permanently to get higher yield
        ICrvDepositor(CONVEX_CRV_DEPOSITOR).deposit(amount, true);
        emit Deposit(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {}

    /*///////////////////////////////////////////////////////////////
                            FUNCTION OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function name() public pure override returns (string memory) {
        return "Curve DAO Token Vault";
    }

    function symbol() public pure override returns (string memory) {
        return "CRVv";
    }

    /// @notice we add more decimals for better precision, it is safe for this specific case
    function decimals() public pure override returns (uint8) {
        return 30;
    }
}
