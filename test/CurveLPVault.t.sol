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
    address constant cvx = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address constant LP_TOKEN = 0x06325440D014e39736583c165C2963BA99fAf14E;
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

    function testFailDepositLPTokensExceedsBalance() public {
        vault.deposit(10000000000000 ether, address(this));
    }

    function testFailDepositLPTokensAmountZero() public {
        vault.deposit(0, address(this));
    }

    function testDepositLPTokens() public returns (uint256 shares) {
        // get Curve LP tokens
        uint256 lpTokens = getLPTokens();
        LP_TOKEN.safeApprove(address(vault), lpTokens);
        // deposit the LP tokens in the vault
        shares = vault.deposit(lpTokens, address(this));
        assertEq(shares, vault.balanceOf(address(this)));
        assertEq(shares, lpTokens);
        assertEq(shares, vault.maxWithdraw(address(this)));
    }

    function testFailRedeemLPTokensAmountExceedsBalance() public {
        vault.redeem(10000, address(this), address(this));
    }

    function testFailRedeemLPTokensInsufficientBalance() public {
        uint256 shares = testDepositLPTokens();
        vault.redeem(shares + 1, address(this), address(this));
    }

    function testRedeemLPTokens() public {
        uint256 shares = testDepositLPTokens();
        uint256 expectedAmountOut = vault.maxWithdraw(address(this));
        uint256 amountOut = vault.redeem(shares, address(this), address(this));
        assertEq(amountOut, expectedAmountOut);
        assertEq(LP_TOKEN.balanceOf(address(this)), amountOut);
        assertEq(vault.balanceOf(address(this)), 0);
    }

    function testCompoundLPTokensRewardsWithoutRewardsAvailable() public {
        testDepositLPTokens();
        assertFalse(vault.compoundRewards());
    }

    function testCompoundLPTokensRewards() public returns (uint256 underlyingBalanceBefore) {
        testDepositLPTokens();
        // more than 1 week afer
        vm.rollFork(block.number + 10_000);
        uint256 crvEarned = rewards.earned(address(vault));
        assertGt(crvEarned, 0);
        uint256 stakedBefore = rewards.balanceOf(address(vault));
        underlyingBalanceBefore = vault.maxWithdraw(address(this));
        assertTrue(vault.compoundRewards());
        uint256 underlyingBalanceAfter = vault.maxWithdraw(address(this));
        assertGt(underlyingBalanceAfter, underlyingBalanceBefore);
        uint256 stakedAfter = rewards.balanceOf(address(vault));
        assertGt(stakedAfter, stakedBefore);
        assertEq(address(vault).balance, 0);
        assertEq(sETH.balanceOf(address(vault)), 0);
        assertEq(cvx.balanceOf(address(vault)), 0);
        assertEq(rewards.earned(address(vault)), 0);
    }

    function testWithdrawLPTokensRewardsWithProfit() public {
        uint256 underlyingBalanceBefore = testCompoundLPTokensRewards();
        assertGt(vault.redeem(vault.balanceOf(address(this)), address(this), address(this)), underlyingBalanceBefore);
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
