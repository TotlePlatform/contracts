// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "./ExchangeHandler.sol";


interface CToken is IERC20 {
    function redeem(uint256 redeemTokens) external returns (uint256);

    function redeemUnderlying(uint256 redeemTokens) external returns (uint256);
}

interface CEther is CToken {
    function mint() external payable;
}

interface CERC20 is CToken {
    function mint(uint256 mintAmount) external returns (uint256);

    function underlying() external view returns (address token);
}

/// @title Handler for Compound exchange
contract CompoundHandler is ExchangeHandler, AllowanceSetter {
    /*
     *   Types
     */
    address constant CETHER_ADDRESS =
        0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;

    struct OrderData {
        address cToken;
        bool isSourceCToken; //True if CToken is source (burn), false if CToken is destination (mint)
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
        uint256 maxToSpend = getMaxToSpend(targetAmount, availableToSpend);
        if (data.cToken == CETHER_ADDRESS) {
            return performEthAction(data, maxToSpend);
        } else {
            return performTokenAction(data, maxToSpend);
        }
    }

    function performTokenAction(
        OrderData memory data,
        uint256 amountToSpend
    )
        internal
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        CERC20 cToken = CERC20(data.cToken);
        IERC20 token = IERC20(cToken.underlying());
        if (data.isSourceCToken) {
            require(cToken.redeem(amountToSpend) == 0, "redeem failed");
            amountSpentOnOrder = amountToSpend;
            amountReceivedFromOrder = token.balanceOf(address(this));
            token.transfer(msg.sender, amountReceivedFromOrder);
        } else {
            approveAddress(address(cToken), address(token));
            require(cToken.mint(amountToSpend) == 0, "redeem failed");
            amountSpentOnOrder = amountToSpend;
            amountReceivedFromOrder = cToken.balanceOf(address(this));
            cToken.transfer(msg.sender, amountReceivedFromOrder);
        }
    }

    function performEthAction(
        OrderData memory data,
        uint256 amountToSpend
    )
        internal
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        CEther cToken = CEther(data.cToken);
        if (data.isSourceCToken) {
            require(cToken.redeem(amountToSpend) == 0, "redeem failed");
            amountSpentOnOrder = amountToSpend;
            amountReceivedFromOrder = address(this).balance;
            payable(msg.sender).transfer(amountReceivedFromOrder);
        } else {
            cToken.mint{value: amountToSpend}();
            amountSpentOnOrder = amountToSpend;
            amountReceivedFromOrder = cToken.balanceOf(address(this));
            cToken.transfer(msg.sender, amountReceivedFromOrder);
        }
    }
}
