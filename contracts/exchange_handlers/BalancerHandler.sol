pragma solidity 0.5.7;
pragma experimental ABIEncoderV2;

import "../lib/SafeMath.sol";
import "../lib/Math.sol";
import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "./ExchangeHandler.sol";
import "../lib/TotleControl.sol";


interface WETH {
    function deposit() external payable;

    function withdraw(uint256 amount) external;
}

interface BPool {
    function swapExactAmountIn(
        address tokenIn,
        uint tokenAmountIn,
        address tokenOut,
        uint minAmountOut,
        uint maxPrice
    ) external returns (uint tokenAmountOut, uint spotPriceAfter);
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
    constructor() public {}

    struct OrderData {
        address pool;
        address tokenIn;
        address tokenOut;
        uint256 maxOrderSpend;
    }

    /*
     *   Public functions
     */

    /*
     *   Internal functions
     */

    function getMaxToSpend(
        uint256 targetAmount,
        uint256 availableToSpend,
        uint256 maxOrderSpend
    ) internal returns (uint256 max) {
        max = Math.min(Math.min(availableToSpend, targetAmount), maxOrderSpend);
        return max;
    }

    function performOrder(
        bytes memory genericPayload,
        uint256 availableToSpend,
        uint256 targetAmount,
        bool targetAmountIsSource
    )
        public
        payable
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        OrderData memory data = abi.decode(genericPayload, (OrderData));

        amountSpentOnOrder = getMaxToSpend(
            targetAmount,
            availableToSpend,
            data.maxOrderSpend
        );
        if (data.tokenIn == address(weth)) {
            weth.deposit.value(amountSpentOnOrder)();
        }
        if (amountSpentOnOrder > 0) {
            BPool pool = BPool(data.pool);
            approveAddress(data.pool, data.tokenIn);
            (amountReceivedFromOrder,) = pool.swapExactAmountIn(
                data.tokenIn,
                amountSpentOnOrder,
                data.tokenOut,
                1,
                Utils.max_uint()
            );
        }

        if (amountSpentOnOrder < availableToSpend) {
            if (data.tokenIn == address(weth)) {
                msg.sender.transfer(availableToSpend - amountSpentOnOrder);
            } else {
                ERC20SafeTransfer.safeTransfer(
                    data.tokenIn,
                    msg.sender,
                    availableToSpend - amountSpentOnOrder
                );
            }
        }

        if (data.tokenOut == address(weth)) {
            weth.withdraw(amountReceivedFromOrder);
            msg.sender.transfer(amountReceivedFromOrder);
        } else {
            ERC20SafeTransfer.safeTransfer(
                data.tokenOut,
                msg.sender,
                amountReceivedFromOrder
            );
        }
    }

    /*
     *   Payable fallback function
     */

    function() external payable {}
}
