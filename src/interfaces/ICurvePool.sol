pragma solidity 0.8.21;

interface ICurvePool {
    function add_liquidity(uint256[2] memory amounts, uint256 min_mint_amount)
        external
        payable
        returns (uint256);
    function calc_token_amount(uint256[2] memory amounts, bool is_deposit)
        external
        view
        returns (uint256);
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy)
        external
        payable
        returns (uint256);
    function coins(uint256) external view returns (address);

    function exchange_underlying(uint256 i, uint256 j, uint256 dx, uint256 min_dy, address receiver)
        external
        payable
        returns (uint256);
}
