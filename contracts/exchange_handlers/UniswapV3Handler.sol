pragma solidity 0.5.7;
pragma experimental ABIEncoderV2;

import "../lib/SafeMath.sol";
import "../lib/Math.sol";
import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "./ExchangeHandler.sol";
import "../lib/TotleControl.sol";
import "../lib/WETH.sol";



interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

  function exactInputSingle(
      ExactInputSingleParams calldata params
  ) external returns (uint256 amountOut);

}


/// @title UniswapV3Handler
/// @notice Handles the all UniswapV3 trades for the primary contract
contract UniswapV3Handler is ExchangeHandler, AllowanceSetter {
    /*
     *   State Variables
     */
    WETH constant weth = WETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ISwapRouter constant ROUTER = ISwapRouter(
        0xE592427A0AEce92De3Edee1F18E0157C05861564
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
        uint24 fee;
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
        address replacedSourceAddress = data.sourceAsset == address(Utils.eth_address()) ? address(weth):data.sourceAsset;
        address replacedDestinationAddress = data.destinationAsset == address(Utils.eth_address()) ? address(weth):data.destinationAsset;
        approveAddress(address(ROUTER), replacedSourceAddress);
        amountSpentOnOrder = getMaxToSpend(
            targetAmount,
            availableToSpend,
            data.maxOrderSpend
        );
        if (data.sourceAsset == Utils.eth_address()) {
            weth.deposit.value(amountSpentOnOrder)();
        }
        if (amountSpentOnOrder > 0) {
            amountReceivedFromOrder = ROUTER.exactInputSingle(ISwapRouter.ExactInputSingleParams(replacedSourceAddress,replacedDestinationAddress, data.fee, address(this),block.timestamp,amountSpentOnOrder,0,0));
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

        if (data.destinationAsset == Utils.eth_address()) {
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


    /*
     *   Payable fallback function
     */

    function() external payable {}
}
