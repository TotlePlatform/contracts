// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

contract ProxyTransferTester {
    function transferETH(address payable recipient) public payable {
        recipient.transfer(msg.value);
    }
}