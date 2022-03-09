// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "./ExchangeHandler.sol";

interface CurveFi is IERC20 {
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
        uint256 targetAmount
    )
        public
        payable
        override
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        OrderData memory data = abi.decode(genericPayload, (OrderData));
        uint256 maxToSpend = getMaxToSpend(
            targetAmount,
            Math.min(availableToSpend, data.maxSpend)
        );
        uint256 startingBalance = IERC20(data.destinationAsset).balanceOf(
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
        uint256 endingBalance = IERC20(data.destinationAsset).balanceOf(
            address(this)
        );
        amountSpentOnOrder = maxToSpend;
        if (amountSpentOnOrder < availableToSpend) {
            SafeERC20.safeTransfer(
                IERC20(data.sourceAsset),
                msg.sender,
                availableToSpend - amountSpentOnOrder
            );
        }
        amountReceivedFromOrder = endingBalance - startingBalance;
        SafeERC20.safeTransfer(
            IERC20(data.destinationAsset),
            msg.sender,
            amountReceivedFromOrder
        );
    }
}
