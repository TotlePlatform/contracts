// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "./ExchangeHandler.sol";

interface IIdleToken{
  function mintIdleToken(uint256 _amount, bool _skipWholeRebalance, address _referral) external returns (uint256 mintedTokens);
  function redeemIdleToken(uint256 _amount) external returns (uint256 redeemedTokens);
}
/// @title Handler for IdleFinance exchange
contract IdleFinanceHandler is ExchangeHandler, AllowanceSetter {
    /*
    *   Types
    */

    struct OrderData {
        address underlyingToken;
        address idleToken;
        bool isRedeem; //True if idleToken is source (burn), false if idleToken is destination (mint)
    }

    /*
    *   Internal functions
    */

    function performOrder(
        bytes memory genericPayload,
        uint256 availableToSpend,
        uint256 targetAmount
    )
        public
        override
        payable
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        OrderData memory data = abi.decode(genericPayload, (OrderData));
        uint256 maxToSpend = getMaxToSpend(
            targetAmount,
            availableToSpend
        );
        IIdleToken idleToken = IIdleToken(data.idleToken);
        IERC20 token = IERC20(data.underlyingToken);
        if (data.isRedeem) {
            amountSpentOnOrder = maxToSpend;
            amountReceivedFromOrder = idleToken.redeemIdleToken(
                maxToSpend
            );
            token.transfer(msg.sender, amountReceivedFromOrder);
        } else {
            approveAddress(address(idleToken), address(token));
            amountSpentOnOrder = maxToSpend;
            amountReceivedFromOrder = idleToken.mintIdleToken(maxToSpend, true, address(0x0000000000000000000000000000000000000000));
            IERC20(address(idleToken)).transfer(msg.sender, amountReceivedFromOrder);
        }
    }


}
