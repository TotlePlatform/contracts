pragma solidity 0.4.25;
pragma experimental ABIEncoderV2;

contract SelectorProvider {
    bytes4 constant getAmountToGive = bytes4(keccak256("getAmountToGive(bytes)"));
    bytes4 constant staticExchangeChecks = bytes4(keccak256("staticExchangeChecks(bytes)"));
    bytes4 constant performBuyOrder = bytes4(keccak256("performBuyOrder(bytes,uint256)"));
    bytes4 constant performSellOrder = bytes4(keccak256("performSellOrder(bytes,uint256)"));

    function getSelector(bytes4 genericSelector) public pure returns (bytes4);
}
