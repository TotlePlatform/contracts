// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "./ExchangeHandler.sol";

interface UniswapExchange {
    //Trading
    //Eth to token
    function ethToTokenTransferInput(
        uint256 min_tokens,
        uint256 deadline,
        address recipient
    ) external payable returns (uint256 tokens_bought);

    function ethToTokenTransferOutput(
        uint256 tokens_bought,
        uint256 deadline,
        address recipient
    ) external payable returns (uint256 eth_sold);

    //Token to eth
    function tokenToEthTransferInput(
        uint256 tokens_sold,
        uint256 min_tokens,
        uint256 deadline,
        address recipient
    ) external returns (uint256 eth_bought);

    function tokenToEthTransferOutput(
        uint256 eth_bought,
        uint256 max_tokens,
        uint256 deadline,
        address recipient
    ) external returns (uint256 tokens_sold);

    //Token to token
    function tokenToTokenTransferInput(
        uint256 tokens_sold,
        uint256 min_tokens_bought,
        uint256 min_eth_bought,
        uint256 deadline,
        address recipient,
        address token_addr
    ) external returns (uint256 tokens_bought);

    function tokenToTokenTransferOutput(
        uint256 tokens_bought,
        uint256 max_tokens_sold,
        uint256 max_eth_sold,
        uint256 deadline,
        address recipient,
        address token_addr
    ) external returns (uint256 tokens_sold);

    // Get Price
    function getEthToTokenInputPrice(uint256 eth_sold)
        external
        view
        returns (uint256);

    function getTokenToEthInputPrice(uint256 tokens_sold)
        external
        view
        returns (uint256);

    function tokenAddress() external view returns (address);
}

interface UniswapFactory {
    function getExchange(address token)
        external
        view
        returns (address exchange);
}

/// @title Handler for Uniswap exchange
contract UniswapHandler is ExchangeHandler, AllowanceSetter {
    /*
     *   Types
     */

    struct OrderData {
        address sourceToken;
        address destinationToken;
        uint256 maxSpend;
    }

    UniswapFactory private uniswapFactory;

    /// @notice Constructor
    constructor(address _uniswapFactory)  {
        uniswapFactory = UniswapFactory(_uniswapFactory);
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
        UniswapExchange ex = UniswapExchange(
            uniswapFactory.getExchange(
                data.sourceToken == Utils.eth_address()
                    ? data.destinationToken
                    : data.sourceToken
            )
        );
        approve(data.sourceToken, address(ex));
        uint256 maxToSpend = getMaxToSpend(
            targetAmount,
            availableToSpend,
            data.maxSpend
        );
        if (data.sourceToken == Utils.eth_address()) {
            return
                performEthToToken(
                    ex,
                    maxToSpend,
                    availableToSpend
                );
        } else if (data.destinationToken == Utils.eth_address()) {
            return
                performTokenToEth(
                    data,
                    ex,
                    maxToSpend,
                    availableToSpend
                );
        } else {
            return
                performTokenToToken(
                    data,
                    ex,
                    maxToSpend,
                    availableToSpend
                );
        }
    }

    function performEthToToken(
        UniswapExchange ex,
        uint256 maxToSpend,
        uint256 availableToSpend
    )
        internal
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        amountReceivedFromOrder = ex.ethToTokenTransferInput{value: maxToSpend}(
            1,
            block.timestamp,
            msg.sender
        );
        amountSpentOnOrder = maxToSpend;
        if (maxToSpend < availableToSpend) {
            payable(msg.sender).transfer(availableToSpend - amountSpentOnOrder);
        }
    }

    function performTokenToEth(
        OrderData memory data,
        UniswapExchange ex,
        uint256 maxToSpend,
        uint256 availableToSpend
    )
        internal
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        amountReceivedFromOrder = ex.tokenToEthTransferInput(
            maxToSpend,
            1,
            block.timestamp,
            msg.sender
        );
        amountSpentOnOrder = maxToSpend;
        if (maxToSpend < availableToSpend) {
            SafeERC20.safeTransfer(
                IERC20(data.sourceToken),
                msg.sender,
                availableToSpend - amountSpentOnOrder
            );
        }
    }

    function performTokenToToken(
        OrderData memory data,
        UniswapExchange ex,
        uint256 maxToSpend,
        uint256 availableToSpend
    )
        internal
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        amountReceivedFromOrder = ex.tokenToTokenTransferInput(
            maxToSpend,
            1,
            1,
            block.timestamp,
            msg.sender,
            data.destinationToken
        );
        amountSpentOnOrder = maxToSpend;
        if (availableToSpend > amountSpentOnOrder) {
            SafeERC20.safeTransfer(
                IERC20(data.sourceToken),
                msg.sender,
                availableToSpend - amountSpentOnOrder
            );
        }
    }

    function getMaxToSpend(
        uint256 targetAmount,
        uint256 availableToSpend,
        uint256 maxOrderSpend
    ) internal pure returns (uint256 max) {
        max = availableToSpend;
        max = Math.min(Math.min(max, targetAmount), maxOrderSpend);
        return max;
    }

    function approve(address token, address taker) internal {
        if (token != Utils.eth_address()) {
            approveAddress(taker, token);
        }
    }

}
