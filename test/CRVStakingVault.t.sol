// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "../src/CRVStakingVault.sol";
import "solady/src/utils/SafeTransferLib.sol";
import "../src/interfaces/IBooster.sol";
import "../src/interfaces/ICurvePool.sol";
import "../src/interfaces/IRewards.sol";

contract CurveLPVaultTest is Test {
    event Deposit(address indexed depositor, uint256 indexed amountUnderlying);
    event Withdraw(
        address indexed withdrawer, uint256 indexed shares, uint256 indexed amountUnderlying
    );

    using SafeTransferLib for address;

    address constant CVXCRV = 0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7;
    address constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    ICurvePool constant TRICRV = ICurvePool(0x4eBdF703948ddCEA3B11f675B4D1Fba9d2414A14);
    CRVStakingVault vault;
    IRewards constant rewards = IRewards(0x3Fe65692bfCD0e6CF84cB1E7d24108E434A7587e);


    uint256 mainnetFork;
    // set up environment variable in .env
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(18_380_900);
        vault = new CRVStakingVault();
    }

    function testFailDepositCRVExceedsBalance() public {
        vault.deposit(10000000000000 ether);
    }

    function testFailDepositCRVAmountZero() public {
        vault.deposit(0);
    }

    function testDepositCRV() public returns (uint256 shares) {
        uint256 crvAmount = getCRV();
        CRV.safeApprove(address(vault), crvAmount);
        vm.expectEmit();
        emit Deposit(address(this), crvAmount);
        shares = vault.deposit(crvAmount);
        assertEq(shares, crvAmount);
        assertEq(CVXCRV.balanceOf(address(vault)), 0);
        assertEq(vault.balanceOfUnderlying(address(this)), crvAmount);
        assertEq(vault.balanceOf(address(this)), crvAmount);
    }

    function testFailWithdrawCRVInsufficientBalance() public {
        uint256 shares = testDepositCRV();
        vault.withdraw(shares + 1, false);
    }

    function testWithdrawCRVNoUnwrap() public {
        uint256 shares = testDepositCRV();
        vm.expectEmit();
        emit Withdraw(address(this), shares, shares);
        uint256 amountOut = vault.withdraw(shares, false);
        assertEq(CVXCRV.balanceOf(address(this)), amountOut);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.balanceOf(address(this)), 0);
    }

    function testWithdrawCRVUnwrap() public {
        uint256 shares = testDepositCRV();
        uint256 expectedCrvAmount = vault.previewUnwrap(shares);
        vm.expectEmit();
        emit Withdraw(address(this), shares, expectedCrvAmount);
        uint256 amountOut = vault.withdraw(shares, true);
        assertEq(CRV.balanceOf(address(this)), amountOut);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.balanceOf(address(this)), 0);
    }

    function testCompoundCRVRewardsWithoutRewardsAvailable() public {
        testDepositCRV();
        assertFalse(vault.compoundRewards());
    }

    function testCompoundCRVRewards() public returns (uint256 underlyingBalanceBefore) {
        testDepositCRV();
        // more than 1 week afer
        vm.rollFork(block.number + 10_000);
        uint256 crvEarned = rewards.earned(address(vault));
        assertGt(crvEarned, 0);
        uint256 stakedBefore = rewards.balanceOf(address(vault));
        underlyingBalanceBefore = vault.balanceOfUnderlying(address(this));
        assertTrue(vault.compoundRewards());
        uint256 underlyingBalanceAfter = vault.balanceOfUnderlying(address(this));
        assertGt(underlyingBalanceAfter, underlyingBalanceBefore);
        uint256 stakedAfter = rewards.balanceOf(address(vault));
        assertGt(stakedAfter, stakedBefore);
        assertEq(address(vault).balance, 0);
        assertEq(CVXCRV.balanceOf(address(vault)), 0);
        assertEq(CRV.balanceOf(address(vault)), 0);
        assertEq(rewards.earned(address(vault)), 0);
    }

    function testWithdrawCRVRewardsWithProfitNoUnwrap() public {
        uint256 underlyingBalanceBefore = testCompoundCRVRewards();
        assertGt(vault.withdraw(vault.balanceOf(address(this)), false), underlyingBalanceBefore);
    }

    function testWithdrawCRVRewardsWithProfitUnwrap() public {
        uint256 underlyingBalanceBefore = testCompoundCRVRewards();
        uint256 underlyingBalanceAfter = vault.balanceOfUnderlying(address(this));
        assertGt(underlyingBalanceAfter, underlyingBalanceBefore);
        uint256 expectedCrv = vault.previewUnwrap(underlyingBalanceAfter);
        assertEq(vault.withdraw(vault.balanceOf(address(this)), true), expectedCrv);
        assertEq(CRV.balanceOf(address(this)), expectedCrv);
    }

    function getCRV() public returns (uint256 crvAmount) {
        crvAmount = TRICRV.exchange_underlying{value: 10 ether}(1, 2, 10 ether, 0, address(this));
    }
}
