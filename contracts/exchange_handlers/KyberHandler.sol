// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "./ExchangeHandler.sol";


interface Kyber {
    function tradeWithHint(
        IERC20 src,
        uint256 srcAmount,
        IERC20 dest,
        address destAddress,
        uint256 maxDestAmount,
        uint256 minConversionRate,
        address walletId,
        bytes calldata hint
    ) external payable returns (uint256);
}

/// @title Interface for all exchange handler contracts
contract KyberHandler is ExchangeHandler, AllowanceSetter {
    /*
     *   State Variables
     */
    Kyber public immutable exchange; // 0x9AAb3f75489902f3a48495025729a0AF77d4b11e on Ethereum mainnet
    address ETH_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    /*
     *   Types
     */

    struct OrderData {
        address tokenFrom;
        address tokenTo;
        uint256 maxSpend;
        bytes hint;
    }

    /// @notice Constructor
    constructor(Kyber _exchange) {
        exchange = _exchange;
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
        uint256 originalBalance = getBalance(data.tokenFrom);
        approve(address(exchange), data.tokenFrom);
        uint256 amountToSpend = Math.min(
            Math.min(
                availableToSpend,
                targetAmount
            ),
            data.maxSpend
        );
        amountReceivedFromOrder = exchange.tradeWithHint{value:
            (data.tokenFrom == Utils.eth_address() ? amountToSpend : 0)
        }(
            IERC20(
                data.tokenFrom == Utils.eth_address()
                    ? ETH_TOKEN_ADDRESS
                    : data.tokenFrom
            ),
            amountToSpend,
            IERC20(
                data.tokenTo == Utils.eth_address()
                    ? ETH_TOKEN_ADDRESS
                    : data.tokenTo
            ),
            msg.sender,
            Utils.max_uint(),
            1,
            address(0x0),
            data.hint
        );
        uint256 newInputBalance = getBalance(data.tokenFrom);
        amountSpentOnOrder = originalBalance - newInputBalance;
        if (amountSpentOnOrder < availableToSpend) {
            if (data.tokenFrom == Utils.eth_address()) {
                payable(msg.sender).transfer(
                    SafeMath.sub(availableToSpend, amountSpentOnOrder)
                );
            } else {
                SafeERC20.safeTransfer(
                    IERC20(data.tokenFrom),
                    msg.sender,
                    SafeMath.sub(availableToSpend, amountSpentOnOrder)
                );
            }
        }
    }

    function approve(address spender, address token) internal {
        if (token != Utils.eth_address()) {
            approveAddress(spender, token);
        }
    }

    function getBalance(address token) internal view returns (uint256 balance) {
        if (token == Utils.eth_address()) {
            return address(this).balance;
        } else {
            return IERC20(token).balanceOf(address(this));
        }
    }

    function transfer(address token, uint256 amount) internal {
        if (token == Utils.eth_address()) {
            payable(msg.sender).transfer(amount);
        } else {
            SafeERC20.safeTransfer(IERC20(token), msg.sender, amount);
        }
    }

}
