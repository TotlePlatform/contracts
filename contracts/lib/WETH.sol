pragma solidity 0.5.7;

interface WETH {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function balanceOf(address account) external returns (uint256);
}
