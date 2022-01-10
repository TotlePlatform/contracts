// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

interface WETH {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function balanceOf(address account) external returns (uint256);
}
