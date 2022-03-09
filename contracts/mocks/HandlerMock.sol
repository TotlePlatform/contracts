// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../lib/Utils.sol";

contract HandlerMock {
    IERC20 public token;
    uint256 priceDivider;

    struct OrderData {
        address sourceAsset;
        address destinationAsset;
        uint256 amount; //Order total amount
    }

    constructor(address _token, uint256 _priceDivider) {
        token = IERC20(_token);
        priceDivider = _priceDivider;
    }

    function getAmountToGive(OrderData memory order)
        internal
        pure
        returns (uint256 amountToGive)
    {
        return order.amount / 2;
    }

    function staticExchangeChecks(OrderData memory order)
        internal
        pure
        returns (bool checksPassed)
    {
        return order.amount > 0;
    }

    function performOrder(
        bytes memory genericPayload,
        uint256 availableToSpend,
        uint256 targetAmount
    )
        external
        payable
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        OrderData memory data = abi.decode(genericPayload, (OrderData));
        amountSpentOnOrder = availableToSpend < targetAmount
            ? availableToSpend
            : targetAmount;
        if (data.sourceAsset == Utils.ETH_ADDRESS) {
            payable(0x0).transfer(targetAmount);
            amountReceivedFromOrder = amountSpentOnOrder * priceDivider;
            token.transfer(msg.sender, amountReceivedFromOrder);
        } else {
            token.transfer(address(0x1), amountSpentOnOrder);
            amountReceivedFromOrder = amountSpentOnOrder / priceDivider;
            payable(msg.sender).transfer(amountReceivedFromOrder);
        }
    }

    receive() external payable {}
}
