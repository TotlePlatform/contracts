// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "./ExchangeHandler.sol";
import "../lib/TotleControl.sol";
import "../lib/WETH.sol";


interface BPool {
    function swapExactAmountIn(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxPrice
    ) external returns (uint256 tokenAmountOut, uint256 spotPriceAfter);
}

/// @title BalancerHandler
/// @notice Handles the all BalancerHandler trades for the primary contract
contract BalancerHandler is ExchangeHandler, AllowanceSetter {
    /*
     *   State Variables
     */
    WETH constant weth = WETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    /*
     *   Types
     */

    /// @notice Constructor
    constructor() {}

    struct OrderData {
        address pool;
        address tokenIn;
        address tokenOut;
        uint256 maxOrderSpend;
    }

    /*
     *   Public functions
     */

    function performOrder(
        bytes memory genericPayload,
        uint256 availableToSpend,
        uint256 targetAmount
    )
        public
        payable
        override
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        OrderData memory data = abi.decode(genericPayload, (OrderData));

        amountSpentOnOrder = getMaxToSpend(
            targetAmount,
            Math.min(availableToSpend, data.maxOrderSpend)
        );
        if (data.tokenIn == address(weth)) {
            weth.deposit{value: amountSpentOnOrder}();
        }
        if (amountSpentOnOrder > 0) {
            BPool pool = BPool(data.pool);
            approveAddress(data.pool, data.tokenIn);
            (amountReceivedFromOrder, ) = pool.swapExactAmountIn(
                data.tokenIn,
                amountSpentOnOrder,
                data.tokenOut,
                1,
                Utils.max_uint()
            );
        }

        if (amountSpentOnOrder < availableToSpend) {
            if (data.tokenIn == address(weth)) {
                payable(msg.sender).transfer(
                    availableToSpend - amountSpentOnOrder
                );
            } else {
                SafeERC20.safeTransfer(
                    IERC20(data.tokenIn),
                    msg.sender,
                    availableToSpend - amountSpentOnOrder
                );
            }
        }

        if (data.tokenOut == address(weth)) {
            weth.withdraw(amountReceivedFromOrder);
            payable(msg.sender).transfer(amountReceivedFromOrder);
        } else {
            SafeERC20.safeTransfer(
                IERC20(data.tokenOut),
                msg.sender,
                amountReceivedFromOrder
            );
        }
    }
}
