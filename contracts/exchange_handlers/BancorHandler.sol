// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "../lib/AllowanceSetter.sol";
import "../lib/Utils.sol";
import "./ExchangeHandler.sol";

/// @title BancorNetwork
/// @notice Bancor Network contract interface
interface BancorNetwork {
    function convertByPath2(
        address[] calldata _path,
        uint256 _amount,
        uint256 _minReturn
    ) external payable returns (uint256);
}

/// @title IBancorGasPriceLimit
/// @notice Bancor gas price limit contract interface
interface IBancorGasPriceLimit {
    function gasPrice() external view returns (uint256);
}

/// @title Interface for all exchange handler contracts
/// @notice Handles the all Bancor trades for the primary contract
contract BancorHandler is ExchangeHandler, AllowanceSetter {
    /*
     *   Types
     */

    struct OrderData {
        address networkAddress;
        address[7] conversionPath;
        address destinationToken;
        uint256 maxSpend;
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
        override
        payable
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        OrderData memory data = abi.decode(genericPayload, (OrderData));
        approve(data.networkAddress, data.conversionPath[0]);
        amountSpentOnOrder = Math.min(
            Math.min(availableToSpend, targetAmount),
            data.maxSpend
        );
        if (msg.value > 0) {
            amountReceivedFromOrder = BancorNetwork(data.networkAddress)
                .convertByPath2{value: (msg.value > 0 ? amountSpentOnOrder : 0)}(
                trimAddressArray(data.conversionPath),
                amountSpentOnOrder,
                1
            );
        } else {
            amountReceivedFromOrder = BancorNetwork(data.networkAddress)
                .convertByPath2(
                    trimAddressArray(data.conversionPath),
                    amountSpentOnOrder,
                    1
                );
        }
        if (amountSpentOnOrder < availableToSpend) {
            if (msg.value > 0) {
                payable(msg.sender).transfer(
                    SafeMath.sub(availableToSpend, amountSpentOnOrder)
                );
            } else {
                SafeERC20.safeTransfer(
                    IERC20(data.conversionPath[0]),
                    msg.sender,
                    SafeMath.sub(availableToSpend, amountSpentOnOrder)
                );
            }
        }
        if (data.destinationToken == Utils.eth_address()) {
            payable(msg.sender).transfer(amountReceivedFromOrder);
        } else {
            SafeERC20.safeTransfer(
                IERC20(data.destinationToken),
                msg.sender,
                amountReceivedFromOrder
            );
        }
    }

    /// @notice Takes the static array, trims the excess and returns a dynamic array
    /// @param addresses the static array
    /// @return address[] the dynamic array
    function trimAddressArray(address[7] memory addresses)
        internal
        pure
        returns (address[] memory)
    {
        uint256 length = 0;
        uint256 index = 0;
        for (index = 0; index < 7; index++) {
            if (addresses[index] == address(0x0)) {
                continue;
            }
            length++;
        }
        address[] memory trimmedArray = new address[](length);
        for (index = 0; index < length; index++) {
            trimmedArray[index] = addresses[index];
        }
        return trimmedArray;
    }

    function approve(address spender, address token) internal {
        if (msg.value == 0) {
            approveAddress(spender, token);
        }
    }
}
