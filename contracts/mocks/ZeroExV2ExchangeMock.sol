// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

contract ZeroExV2ExchangeMock {

    function getAssetProxy(bytes4 ) public pure returns (address) {
        return 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    }
}
