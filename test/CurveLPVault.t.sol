// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "../src/CurveLPVault.sol";
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

    address constant sETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    // ETH/sETH LP token
    address constant LP_TOKEN = 0x06325440D014e39736583c165C2963BA99fAf14E;
    // ETH/sETH pool
    ICurvePool constant POOL = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);
    CurveLPVault vault;
    IRewards constant rewards = IRewards(0x0A760466E1B4621579a82a39CB56Dda2F4E70f03); 
    uint256 mainnetFork;
    // set up environment variable in .env
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(18_380_900);
        vault = new CurveLPVault();
    }

    function testFailDepositExceedsBalance() public {
        vault.deposit(10000000000000 ether);
    }

    function testFailDepositAmountZero() public {
        vault.deposit(0);
    }

    function testDeposit() public returns (uint256 shares) {
        // get Curve LP tokens
        uint256 lpTokens = getLPTokens();
        LP_TOKEN.safeApprove(address(vault), lpTokens);
        // deposit the LP tokens in the vault
        vm.expectEmit();
        emit Deposit(address(this), lpTokens);
        shares = vault.deposit(lpTokens);
        assertEq(shares, vault.balanceOf(address(this)));
        assertEq(shares, lpTokens);
        assertEq(shares, vault.balanceOfUnderlying(address(this)));
    }

    function testFailWithdrawAmountExceedsBalance() public {
        vault.withdraw(10000);
    }

    function testWithdraw() public {
        uint256 shares = testDeposit();
        vm.expectEmit();
        uint256 expectedAmountOut = vault.balanceOfUnderlying(address(this));
        emit Withdraw(address(this), shares,expectedAmountOut );
        uint256 amountOut = vault.withdraw(shares);
        assertEq(amountOut, expectedAmountOut);
        assertEq(LP_TOKEN.balanceOf(address(this)), amountOut);
        assertEq(vault.balanceOf(address(this)), 0);
    }

    function testCompoundRewardsWithoutRewardsAvailable() public {
        testDeposit();
        assertEq(rewards.earned(address(vault)) , 0);
        assertFalse(vault.compoundRewards());
    } 

    function testCompoundRewards() public returns(uint256 underlyingBalanceBefore){
        testDeposit();
        // more than 1 week afer
        vm.rollFork(block.number + 10_000);
        uint256 crvEarned = rewards.earned(address(vault));
        assertGt(crvEarned , 0);
        uint256 stakedBefore = rewards.balanceOf(address(vault));
        underlyingBalanceBefore = vault.balanceOfUnderlying(address(this));
        assertTrue(vault.compoundRewards());
        uint256 underlyingBalanceAfter = vault.balanceOfUnderlying(address(this));
        assertGt(underlyingBalanceAfter, underlyingBalanceBefore);
        uint256 stakedAfter = rewards.balanceOf(address(vault));
        assertGt(stakedAfter, stakedBefore);
    }

    function testWithdrawRewardsWithProfit() public {
        uint256 underlyingBalanceBefore = testCompoundRewards();
        assertGt(vault.withdraw(vault.balanceOf(address(this))),underlyingBalanceBefore);
    }

    // add liquidity to ETH/stETH to get LP tokens
    function getLPTokens() internal returns (uint256 mintedLiquidity) {
        uint256 ETHAmount = 10 ether;
        // swap to have both ETH and stETH
        uint256 sETHAmount = POOL.exchange{value: ETHAmount}(0, 1, ETHAmount, 0);
        sETH.safeApprove(address(POOL), sETHAmount);
        uint256[2] memory amounts = [ETHAmount, sETHAmount];
        // deposit liquidity
        mintedLiquidity = POOL.add_liquidity{value: ETHAmount}(amounts, 0);
    }
}
