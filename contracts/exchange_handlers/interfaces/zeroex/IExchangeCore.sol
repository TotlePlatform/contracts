// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./LibOrder.sol";
import "./LibFillResults.sol";

abstract contract IExchangeCore {
    bytes public ZRX_ASSET_DATA;

    /// @dev Fills the input order.
    /// @param order Order struct containing order specifications.
    /// @param takerAssetFillAmount Desired amount of takerAsset to sell.
    /// @param signature Proof that order has been created by maker.
    /// @return fillResults Amounts filled and fees paid by maker and taker.
    function fillOrder(
        LibOrder.Order memory order,
        uint256 takerAssetFillAmount,
        bytes memory signature
    ) external virtual returns (LibFillResults.FillResults memory fillResults);

    function fillOrderNoThrow(
        LibOrder.Order memory order,
        uint256 takerAssetFillAmount,
        bytes memory signature
    ) external virtual returns (LibFillResults.FillResults memory fillResults);

    /// @dev Gets information about an order: status, hash, and amount filled.
    /// @param order Order to gather information on.
    /// @return orderInfo Information about the order and its state. See LibOrder.OrderInfo for a complete description.
    function getOrderInfo(LibOrder.Order memory order)
        external
        view
        virtual
        returns (LibOrder.OrderInfo memory orderInfo);

    /// @dev Gets an asset proxy.
    /// @param assetProxyId Id of the asset proxy.
    /// @return The asset proxy registered to assetProxyId. Returns 0x0 if no proxy is registered.
    function getAssetProxy(bytes4 assetProxyId)
        external
        view
        virtual
        returns (address);

    function isValidSignature(
        bytes32 hash,
        address signerAddress,
        bytes memory signature
    ) external view virtual returns (bool isValid);
}
