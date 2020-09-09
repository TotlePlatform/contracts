pragma solidity 0.5.7;
pragma experimental ABIEncoderV2;

import "../lib/SafeMath.sol";
import "../lib/Math.sol";
import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "./ExchangeHandler.sol";
import "../lib/TotleControl.sol";
import "../lib/WETH.sol";

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);
}


interface IUniswapV2Pair {
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}


/// @title UniswapV2Handler
/// @notice Handles the all ZeroExExchange trades for the primary contract
contract UniswapV2Handler is ExchangeHandler, AllowanceSetter {
    /*
     *   State Variables
     */
    WETH constant weth = WETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IUniswapV2Factory constant factory = IUniswapV2Factory(
        0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f
    );

    /*
     *   Types
     */

    /// @notice Constructor
    constructor() public {}

    struct OrderData {
        address sourceAsset;
        address destinationAsset;
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
        if (data.sourceAsset == address(weth)) {
            weth.deposit.value(amountSpentOnOrder)();
        }
        if (amountSpentOnOrder > 0) {
            amountReceivedFromOrder = swap(
                amountSpentOnOrder,
                data.sourceAsset,
                data.destinationAsset
            );
        }

        if (amountSpentOnOrder < availableToSpend) {
            if (data.sourceAsset == address(weth)) {
                msg.sender.transfer(availableToSpend - amountSpentOnOrder);
            } else {
                ERC20SafeTransfer.safeTransfer(
                    data.sourceAsset,
                    msg.sender,
                    availableToSpend - amountSpentOnOrder
                );
            }
        }

        if (data.destinationAsset == address(weth)) {
            weth.withdraw(amountReceivedFromOrder);
            msg.sender.transfer(amountReceivedFromOrder);
        } else {
            ERC20SafeTransfer.safeTransfer(
                data.destinationAsset,
                msg.sender,
                amountReceivedFromOrder
            );
        }
    }

    function swap(uint256 amount, address sourceToken, address destinationToken)
        private
        returns (uint256 output)
    {
        // Sort the tokens. This is used for getting reserves
        (address token0, address token1) = sourceToken < destinationToken
            ? (sourceToken, destinationToken)
            : (destinationToken, sourceToken);

        // Get the pair contract
        IUniswapV2Pair pair = IUniswapV2Pair(
            address(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            factory,
                            keccak256(abi.encodePacked(token0, token1)),
                            hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f" // init code hash
                        )
                    )
                )
            )
        );
        // Get the reserves
        (uint256 sourceReserve, uint256 destinationReserve, ) = pair
            .getReserves();
        // Reorder the reserves if need be
        (sourceReserve, destinationReserve) = sourceToken == token0
            ? (sourceReserve, destinationReserve)
            : (destinationReserve, sourceReserve);
        // Get the output amount using the source amount, source reserve, and destination reserve
        output = getAmountOut(amount, sourceReserve, destinationReserve);
        // Transfer the source tokens to the pair contract
        ERC20SafeTransfer.safeTransfer(sourceToken, address(pair), amount);
        // Call swap
        pair.swap(
            destinationToken == token0 ? output : 0,
            destinationToken == token0 ? 0 : output,
            address(this),
            new bytes(0)
        );
    }

    function sortTokens(address tokenA, address tokenB)
        internal
        pure
        returns (address token0, address token1)
    {}

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        uint256 amountInWithFee = SafeMath.mul(amountIn, 997);
        uint256 numerator = SafeMath.mul(amountInWithFee, reserveOut);
        uint256 denominator = SafeMath.add(
            SafeMath.mul(reserveIn, 1000),
            amountInWithFee
        );
        amountOut = numerator / denominator;
    }

    /*
     *   Payable fallback function
     */

    function() external payable {}
}
