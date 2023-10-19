// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IBooster} from "./interfaces/IBooster.sol";
import {ICrvDepositor} from "./interfaces/ICrvDepositor.sol";

/// @notice best approach would be ERC4626 but since you asked for {deposit} and {withdraw} functions only:
contract CurveLPVault is ERC20 {
    error CurveLPVault__Deposit_AmountIsZero();

    event Deposit(address indexed depositor, uint256 indexed amount);

    using SafeTransferLib for address;

    /// @notice Curve USTPFRAXBP pool LP token
    address public constant UNDERLYNG_ASSET = 0x8e9De7E69424c848972870798286E8bc5EcB295F;

    /// @notice Convex main deposit contract
    address public constant CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;

    /// @notice The id of the pool in Booster
    uint256 constant POOL_ID = 3;

    /// @notice constant for scaling decimals from CRV amount to share amount
    uint256 constant PRECISION = 10 ** 12; // 30 -18

    function deposit(uint256 amount) external {
        if (amount == 0) revert CurveLPVault__Deposit_AmountIsZero();
        UNDERLYNG_ASSET.safeTransferFrom(msg.sender, address(this), amount);
        UNDERLYNG_ASSET.safeApprove(CONVEX_BOOSTER, amount);
        IBooster(CONVEX_BOOSTER).deposit(POOL_ID, amount, false);
        _mint(msg.sender, amount * PRECISION);
    }

    function withdraw(uint256 amount) external {}

    /*///////////////////////////////////////////////////////////////
                            FUNCTION OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function name() public pure override returns (string memory) {
        return "Curve.fi Factory USD Metapool: USTPFRAXBP Vault";
    }

    function symbol() public pure override returns (string memory) {
        return "USTPFRAXBP3CRV-fv";
    }

    /// @notice we add more decimals for better precision, it is safe for this specific case
    function decimals() public pure override returns (uint8) {
        return 30;
    }
}
