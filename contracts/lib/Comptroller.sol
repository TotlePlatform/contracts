pragma solidity 0.5.7;

contract Comptroller {
    struct Market {
        /**
         * @notice Whether or not this market is listed
         */
        bool isListed;

        /**
         * @notice Multiplier representing the most one can borrow against their collateral in this market.
         *  For instance, 0.9 to allow borrowing 90% of collateral value.
         *  Must be between 0 and 1, and stored as a mantissa.
         */
        uint collateralFactorMantissa;

        /**
         * @notice Per-market mapping of "accounts in this asset"
         */
        mapping(address => bool) accountMembership;
    }
  function getAccountLiquidity(address account) external view returns (uint, uint, uint);
  function oracle() external view returns (address);
  function transferAllowed(address cToken, address src, address dst, uint transferTokens) external returns (uint);
  function markets(address) external view returns (bool, uint256);
}
