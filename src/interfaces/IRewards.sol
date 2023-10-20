pragma solidity 0.8.21;

interface IRewards {
    function stake(address, uint256) external;
    function stakeFor(address, uint256) external;
    function withdraw(uint256, bool) external returns (bool);
    function withdrawAndUnwrap(uint256 amount, bool claim) external returns (bool);
    function exit(address) external;
    function getReward(address, bool) external returns (bool);
    function queueNewRewards(uint256) external;
    function notifyRewardAmount(uint256) external;
    function addExtraReward(address) external;
    function stakingToken() external view returns (address);
    function rewardToken() external view returns (address);
    function earned(address account) external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
}
