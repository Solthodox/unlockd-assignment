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

    // ETH/sETH LP token
    address constant LP_TOKEN = 0x06325440D014e39736583c165C2963BA99fAf14E;
    // ETH/sETH pool
    ICurvePool constant POOL = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);
    CRVStakingVault vault;
    IRewards constant rewards = IRewards(0x0A760466E1B4621579a82a39CB56Dda2F4E70f03); 
    uint256 mainnetFork;
    // set up environment variable in .env
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(18_380_900);
        vault = new CRVStakingVault();
    }

}
