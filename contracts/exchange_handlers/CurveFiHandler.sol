pragma solidity 0.5.7;
pragma experimental ABIEncoderV2;

import "../lib/ERC20.sol";
import "../lib/SafeMath.sol";
import "../lib/Math.sol";
import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "../lib/ERC20SafeTransfer.sol";
import "./ExchangeHandler.sol";

contract CurveFi is ERC20 {
    function exchange_underlying(
        int128 sourceAssetId,
        int128 destinationAssetId,
        uint256 sourceAmount,
        uint256 minimumDestinationAmount,
        uint256 deadline
    ) external;

    function exchange_underlying(
        int128 sourceAssetId,
        int128 destinationAssetId,
        uint256 sourceAmount,
        uint256 minimumDestinationAmount
    ) external;

    function exchange(
        int128 sourceAssetId,
        int128 destinationAssetId,
        uint256 sourceAmount,
        uint256 minimumDestinationAmount
    ) external;
}

/// @title Handler for Compound exchange
contract CurveFiHandler is ExchangeHandler, AllowanceSetter {
    struct OrderData {
        int128 sourceAssetId;
        int128 destinationAssetId;
        address sourceAsset;
        address destinationAsset;
        address curveFi;
        uint256 version;
        uint256 maxSpend;
    }

    /*
     *   Internal functions
     */

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
        uint256 maxToSpend = getMaxToSpend(
            targetAmount,
            availableToSpend,
            data.maxSpend
        );
        uint256 startingBalance = ERC20(data.destinationAsset).balanceOf(
            address(this)
        );
        CurveFi curveFi = CurveFi(data.curveFi);
        approveAddress(address(curveFi), data.sourceAsset);
        if (data.version == 1) {
            curveFi.exchange_underlying(
                data.sourceAssetId,
                data.destinationAssetId,
                maxToSpend,
                1
            );
        } else if (data.version == 2) {
            curveFi.exchange(
                data.sourceAssetId,
                data.destinationAssetId,
                maxToSpend,
                1
            );
        }
        uint256 endingBalance = ERC20(data.destinationAsset).balanceOf(
            address(this)
        );
        amountSpentOnOrder = maxToSpend;
        if (amountSpentOnOrder < availableToSpend) {
            require(
                ERC20SafeTransfer.safeTransfer(
                    data.sourceAsset,
                    msg.sender,
                    availableToSpend - amountSpentOnOrder
                ),
                "Token transfer failed"
            );
        }
        amountReceivedFromOrder = endingBalance - startingBalance;
        require(
            ERC20SafeTransfer.safeTransfer(
                data.destinationAsset,
                msg.sender,
                amountReceivedFromOrder
            ),
            "Token transfer failed"
        );
    }

    function getMaxToSpend(
        uint256 targetAmount,
        uint256 availableToSpend,
        uint256 maxOrderSpend
    ) internal returns (uint256 max) {
        return
            Math.min(Math.min(availableToSpend, targetAmount), maxOrderSpend);
    }
}
