pragma solidity 0.5.7;
pragma experimental ABIEncoderV2;

import "../lib/ERC20.sol";
import "../lib/SafeMath.sol";
import "../lib/Math.sol";
import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "./ExchangeHandler.sol";



contract CToken is ERC20 {
    function redeem(uint redeemTokens) external returns (uint);
    function redeemUnderlying(uint redeemTokens) external returns (uint);
}

contract CEther is CToken {
    function mint() external payable;
}

contract CERC20 is CToken {
    function mint(uint mintAmount) external returns (uint);  
    function underlying() external view returns (address token);
}

/// @title Handler for Compound exchange
contract CompoundHandler is ExchangeHandler, AllowanceSetter {
    /*
    *   Types
    */
    address constant CETHER_ADDRESS = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;

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
        uint256 targetAmount,
        bool targetAmountIsSource
    )
        public
        payable
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        OrderData memory data = abi.decode(genericPayload, (OrderData));
        uint256 maxToSpend = getMaxToSpend(targetAmountIsSource, targetAmount, availableToSpend);
        if(data.cToken == CETHER_ADDRESS){
            return performEthAction(data, targetAmountIsSource, targetAmount, maxToSpend);
        } else {
            return performTokenAction(data, targetAmountIsSource, targetAmount, maxToSpend);
        }

    }


    function performTokenAction(
        OrderData memory data,
        bool targetAmountIsSource,
        uint256 targetAmount,
        uint256 maxToSpend
    )
        internal
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        CERC20 cToken = CERC20(data.cToken);
        ERC20 token = ERC20(cToken.underlying());
        if(data.isSourceCToken){
            if(targetAmountIsSource){
                cToken.redeem(maxToSpend);
                amountSpentOnOrder = maxToSpend;
            } else {
                cToken.redeemUnderlying(targetAmount);
                amountSpentOnOrder = targetAmount;
            }
            amountReceivedFromOrder = token.balanceOf(address(this));
            token.transfer(msg.sender, amountReceivedFromOrder);
        } else {
            approveAddress(address(cToken), address(token));
            cToken.mint(maxToSpend);
            amountSpentOnOrder = maxToSpend;
            amountReceivedFromOrder = cToken.balanceOf(address(this));
            cToken.transfer(msg.sender, amountReceivedFromOrder);
        }
    }

    function performEthAction(
        OrderData memory data,
        bool targetAmountIsSource,
        uint256 targetAmount,
        uint256 maxToSpend
    )
        internal
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        CEther cToken = CEther(data.cToken);
        if(data.isSourceCToken){
            if(targetAmountIsSource){
                cToken.redeem(maxToSpend);
                amountSpentOnOrder = maxToSpend;
            } else {
                cToken.redeemUnderlying(targetAmount);
                amountSpentOnOrder = targetAmount;
            }
            amountReceivedFromOrder = address(this).balance;
            msg.sender.transfer(amountReceivedFromOrder);
        } else {
            cToken.mint.value(maxToSpend)();
            amountSpentOnOrder = maxToSpend;
            amountReceivedFromOrder = cToken.balanceOf(address(this));
            cToken.transfer(msg.sender, amountReceivedFromOrder);
        }
    }

    function getMaxToSpend(
        bool targetAmountIsSource,
        uint256 targetAmount,
        uint256 availableToSpend
    )
        internal
        returns (uint256 max)
    {
        max = availableToSpend;
        if(targetAmountIsSource){
            max = Math.min(max, targetAmount);
        }
        return max;
    }

  

    /// @notice payable fallback to block EOA sending eth
    function() external payable {
        
    }
}
