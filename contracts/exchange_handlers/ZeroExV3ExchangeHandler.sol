// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "./ExchangeHandler.sol";
import "./interfaces/zeroex/IExchangeCoreV3.sol";
import "../lib/TotleControl.sol";
import "../lib/WETH.sol";

/// @title ZeroExExchangeHandler
/// @notice Handles the all ZeroExExchange trades for the primary contract
contract ZeroExV3ExchangeHandler is ExchangeHandler, AllowanceSetter {
    /*
     *   State Variables
     */
    uint256 constant PROTOCOL_FEE_CONSTANT = 150000;
    IExchangeCore public exchange;
    /// @dev note that this is dependent on the deployment of 0xV3. This is the ERC20 asset proxy + the mainnet address of the ZRX token
    bytes constant ZRX_ASSET_DATA =
        "\xf4\x72\x61\xb0\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xe4\x1d\x24\x89\x57\x1d\x32\x21\x89\x24\x6d\xaf\xa5\xeb\xde\x1f\x46\x99\xf4\x98";
    address ERC20_ASSET_PROXY;
    WETH weth;

    /*
     *   Types
     */

    /// @notice Constructor
    /// @param _exchange Address of the IExchangeCore exchange
    constructor(address _exchange, address _weth) {
        exchange = IExchangeCore(_exchange);
        ERC20_ASSET_PROXY = exchange.getAssetProxy(toBytes4(ZRX_ASSET_DATA, 0));
        weth = WETH(_weth);
    }

    struct OrderData {
        address makerAddress; // Address that created the order.
        address takerAddress; // Address that is allowed to fill the order. If set to 0, any address is allowed to fill the order.
        address feeRecipientAddress; // Address that will recieve fees when order is filled.
        address senderAddress; // Address that is allowed to call Exchange contract methods that affect this order. If set to 0, any address is allowed to call these methods.
        uint256 makerAssetAmount; // Amount of makerAsset being offered by maker. Must be greater than 0.
        uint256 takerAssetAmount; // Amount of takerAsset being bid on by maker. Must be greater than 0.
        uint256 makerFee; // Amount of ZRX paid to feeRecipient by maker when order is filled. If set to 0, no transfer of ZRX from maker to feeRecipient will be attempted.
        uint256 takerFee; // Amount of ZRX paid to feeRecipient by taker when order is filled. If set to 0, no transfer of ZRX from taker to feeRecipient will be attempted.
        uint256 expirationTimeSeconds; // Timestamp in seconds at which order expires.
        uint256 salt; // Arbitrary number to facilitate uniqueness of the order's hash.
        bytes makerAssetData; // Encoded data that can be decoded by a specified proxy contract when transferring makerAsset. The last byte references the id of this proxy.
        bytes takerAssetData; // Encoded data that can be decoded by a specified proxy contract when transferring takerAsset. The last byte references the id of this proxy.
        bytes makerFeeAssetData; // Encoded data that represents data for the maker fee asset
        bytes takerFeeAssetData; // Encoded data that represents data for the taker fee asset
        bytes signature;
    }

    /*
     *   Public functions
     */

    /*
     *   Internal functions
     */

    /// @notice Gets the amount that Totle needs to give for this order
    /// @param data LibOrder.Order struct containing order values
    /// @return amountToGive amount taker needs to give in order to fill the order
    function getAmountToGive(OrderData memory data)
        internal
        view
        returns (uint256 amountToGive)
    {
        LibOrder.OrderInfo memory orderInfo = exchange.getOrderInfo(
            getZeroExOrder(data)
        );
        if (orderInfo.orderStatus != 3) {
            return 0;
        }
        uint256 makerAssetAvailable = getAssetDataAvailable(
            data.makerAssetData,
            data.makerAddress
        );

        uint256 maxFromMakerFee = data.makerFee == 0
            ? Utils.max_uint()
            : getPartialAmount(
                getAssetDataAvailable(
                    data.makerFeeAssetData,
                    data.makerAddress
                ),
                data.makerFee,
                data.takerAssetAmount
            );
        amountToGive = Math.min(
            Math.min(
                getPartialAmount(
                    makerAssetAvailable,
                    data.makerAssetAmount,
                    data.takerAssetAmount
                ),
                maxFromMakerFee
            ),
            SafeMath.sub(
                data.takerAssetAmount,
                orderInfo.orderTakerAssetFilledAmount
            )
        );
    }

    function getAssetDataAvailable(bytes memory assetData, address account)
        internal
        view
        returns (uint256)
    {
        address tokenAddress = toAddress(assetData, 16);
        IERC20 token = IERC20(tokenAddress);
        return
            Math.min(
                token.balanceOf(account),
                token.allowance(account, ERC20_ASSET_PROXY)
            );
    }

    function getZeroExOrder(OrderData memory data)
        internal
        pure
        returns (LibOrder.Order memory)
    {
        return
            LibOrder.Order({
                makerAddress: data.makerAddress,
                takerAddress: data.takerAddress,
                feeRecipientAddress: data.feeRecipientAddress,
                senderAddress: data.senderAddress,
                makerAssetAmount: data.makerAssetAmount,
                takerAssetAmount: data.takerAssetAmount,
                makerFee: data.makerFee,
                takerFee: data.takerFee,
                expirationTimeSeconds: data.expirationTimeSeconds,
                salt: data.salt,
                makerAssetData: data.makerAssetData,
                takerAssetData: data.takerAssetData,
                makerFeeAssetData: data.makerFeeAssetData,
                takerFeeAssetData: data.takerFeeAssetData
            });
    }

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
        address sourceAddress = toAddress(data.takerAssetData, 16);
        if (sourceAddress == address(weth)) {
            require(msg.value == availableToSpend);
        }
        uint256 amountToGive = getAmountToGive(data);
        if (sourceAddress == address(weth)) {
            weth.deposit{value: availableToSpend}();
        }
        if (amountToGive > 0) {
            approveAddress(ERC20_ASSET_PROXY, sourceAddress);

            LibFillResults.FillResults memory results = exchange.fillOrder{
                value: PROTOCOL_FEE_CONSTANT * tx.gasprice
            }(
                getZeroExOrder(data),
                Math.min(
                    targetAmount,
                    Math.min(availableToSpend, amountToGive)
                ),
                data.signature
            );

            amountSpentOnOrder = results.takerAssetFilledAmount;
            amountReceivedFromOrder = results.makerAssetFilledAmount;
        }

        if (amountSpentOnOrder < availableToSpend) {
            if (sourceAddress == address(weth)) {
                weth.withdraw(availableToSpend - amountSpentOnOrder);
                payable(msg.sender).transfer(
                    availableToSpend - amountSpentOnOrder
                );
            } else {
                SafeERC20.safeTransfer(
                    IERC20(sourceAddress),
                    msg.sender,
                    availableToSpend - amountSpentOnOrder
                );
            }
        }

        address destinationAddress = toAddress(data.makerAssetData, 16);

        if (destinationAddress == address(weth)) {
            weth.withdraw(amountReceivedFromOrder);
            payable(msg.sender).transfer(amountReceivedFromOrder);
        } else {
            SafeERC20.safeTransfer(
                IERC20(destinationAddress),
                msg.sender,
                amountReceivedFromOrder
            );
        }
    }

    /// @notice Calculate the result of ((numerator * target) / denominator)
    /// @param numerator the numerator in the equation
    /// @param denominator the denominator in the equation
    /// @param target the target for the equations
    /// @return partialAmount the resultant value
    function getPartialAmount(
        uint256 numerator,
        uint256 denominator,
        uint256 target
    ) internal pure returns (uint256) {
        return SafeMath.div(SafeMath.mul(numerator, target), denominator);
    }

    // @notice Extract an address from a string of bytes
    // @param _bytes a string of at least 20 bytes
    // @param _start the offset of the address within the byte stream
    // @return tempAddress the address encoded in the bytestring beginning at _start
    function toAddress(bytes memory _bytes, uint256 _start)
        internal
        pure
        returns (address)
    {
        require(_bytes.length >= (_start + 20));
        address tempAddress;

        assembly {
            tempAddress := div(
                mload(add(add(_bytes, 0x20), _start)),
                0x1000000000000000000000000
            )
        }

        return tempAddress;
    }

    function toBytes4(bytes memory _bytes, uint256 _start)
        internal
        pure
        returns (bytes4)
    {
        require(_bytes.length >= (_start + 4));
        bytes4 tempBytes4;

        assembly {
            tempBytes4 := mload(add(add(_bytes, 0x20), _start))
        }
        return tempBytes4;
    }

    // @notice Extract a uint256 from a string of bytes
    // @param _bytes a string of at least 32 bytes
    // @param _start the offset of the uint256 within the byte stream
    // @return tempUint the uint encoded in the bytestring beginning at _start
    function toUint(bytes memory _bytes, uint256 _start)
        internal
        pure
        returns (uint256)
    {
        require(_bytes.length >= (_start + 32));
        uint256 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x20), _start))
        }

        return tempUint;
    }
}
