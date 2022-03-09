// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "./ExchangeHandler.sol";

interface IIEarnToken {
    function deposit(uint256 _amount) external;

    function withdraw(uint256 _shares) external;
}


/// @title Handler for IEarnFinance exchange
contract IEarnFinanceHandler is ExchangeHandler, AllowanceSetter {
    /*
     *   Types
     */

    struct OrderData {
        address underlyingToken;
        address iEarnToken;
        bool isRedeem; //True if iEarnToken is source (burn), false if iEarnToken is destination (mint)
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
        IIEarnToken iEarnToken = IIEarnToken(data.iEarnToken);
        IERC20 token = IERC20(data.underlyingToken);
        if (data.isRedeem) {
            amountSpentOnOrder = maxToSpend;
            iEarnToken.withdraw(maxToSpend);
            amountReceivedFromOrder = token.balanceOf(address(this));
            SafeERC20.safeTransfer(
                token,
                msg.sender,
                amountReceivedFromOrder
            );
        } else {
            approveAddress(address(iEarnToken), address(token));
            amountSpentOnOrder = maxToSpend;
            iEarnToken.deposit(maxToSpend);
            amountReceivedFromOrder = IERC20(address(iEarnToken)).balanceOf(
                address(this)
            );
            IERC20(address(iEarnToken)).transfer(
                msg.sender,
                amountReceivedFromOrder
            );
        }

        if (maxToSpend < availableToSpend) {
            if (data.isRedeem) {
                IERC20(address(iEarnToken)).transfer(
                    msg.sender,
                    availableToSpend - maxToSpend
                );
            } else {
                SafeERC20.safeTransfer(
                    token,
                    msg.sender,
                    availableToSpend - maxToSpend
                );
            }
        }
    }

}
