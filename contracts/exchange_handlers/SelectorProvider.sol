pragma solidity 0.4.25;
pragma experimental ABIEncoderV2;

contract SelectorProvider {
    bytes4 constant getAmountToGiveSelector = bytes4(keccak256("getAmountToGive(bytes)"));
    bytes4 constant staticExchangeChecksSelector = bytes4(keccak256("staticExchangeChecks(bytes)"));
    bytes4 constant performBuyOrderSelector = bytes4(keccak256("performBuyOrder(bytes,uint256)"));
    bytes4 constant performSellOrderSelector = bytes4(keccak256("performSellOrder(bytes,uint256)"));

    function getSelector(bytes4 genericSelector) public pure returns (bytes4);
}
