pragma solidity 0.5.7;
pragma experimental ABIEncoderV2;

import "../lib/ERC20.sol";
import "../lib/SafeMath.sol";
import "../lib/Math.sol";
import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "./ExchangeHandler.sol";

interface TokenStoreExchange {
   //Balance deposit/withdraw functions
   function deposit() external payable; //Deposit ETH
   function withdraw(uint256 amount) external; //Withdraw ETH
   function depositToken(address _token, uint _amount) external;
   function withdrawToken(address _token, uint _amount) external;
   //Trading
   function trade(address _tokenGet, uint _amountGet, address _tokenGive, uint _amountGive,
       uint _expires, uint _nonce, address _user, uint8 _v, bytes32 _r, bytes32 _s, uint _amount) external;

   // Get info
   function fee() external view returns(uint256);
   function availableVolume(address _tokenGet, uint _amountGet, address _tokenGive, uint _amountGive, uint _expires,
       uint _nonce, address _user, uint8 _v, bytes32 _r, bytes32 _s) external view returns(uint);


}

/// @title Handler for TokenStore exchange
contract TokenStoreHandler is ExchangeHandler, AllowanceSetter {

    /*
    *   State Variables
    */

    TokenStoreExchange public exchange;

    /*
    *   Types
    */
   struct OrderData {
        address user;
        address tokenGive;
        address tokenGet;
        uint256 amountGive;
        uint256 amountGet;
        uint256 expires;
        uint256 nonce;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }



    /// @notice Constructor
    /// @param _exchange the address of the token store exchange
    constructor(
        address _exchange
        /*,address logger*/
    ) 
        public
    {
        exchange = TokenStoreExchange(_exchange);
    }

    /*
    *   Internal functions
    */


    /// @notice Gets the amount that TotlePrimary needs to give for this order
    /// @param data OrderData struct containing order values
    /// @return amountToGive amount taker needs to give in order to fill the order
    function getAmountToGive(
        OrderData memory data
    )
        internal
        view
        returns (uint256 amountToGive)
    {
        uint256 feePercentage = exchange.fee();
        uint256 availableVolume = exchange.availableVolume(data.tokenGet, data.amountGet, data.tokenGive, data.amountGive, data.expires,
            data.nonce, data.user, data.v, data.r, data.s);
        uint256 fee = SafeMath.div(SafeMath.mul(availableVolume, feePercentage), 1 ether);
        return SafeMath.add(availableVolume, fee);
    }



    /// @notice Perform exchange-specific checks on the given order
    /// @dev This should be called to check for payload errors
    /// @param data OrderData struct containing order values
    /// @return checksPassed value representing pass or fail
    function staticExchangeChecks(
        OrderData memory data
    )
        internal
        view
        returns (bool checksPassed)
    {
        return block.number <= data.expires;
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
        if(!staticExchangeChecks(data)){
            if(data.tokenGet == Utils.eth_address()){
                msg.sender.transfer(availableToSpend);
            } else {
                ERC20SafeTransfer.safeTransfer(data.tokenGive, msg.sender, availableToSpend);
            }
        }
        uint256 feePercentage = exchange.fee();
        approve(data.tokenGet);
        amountSpentOnOrder = Math.min(Math.min(availableToSpend, targetAmount), addFee(feePercentage, getAvailableVolume(data)));
        uint256 amountToTrade;
        uint256 fee;
        (amountToTrade, fee) = subtractFee(feePercentage, amountSpentOnOrder);
        amountReceivedFromOrder = getPartialAmount(data.amountGive, data.amountGet, amountToTrade);

        deposit(data.tokenGet, amountSpentOnOrder);
        exchange.trade(data.tokenGet, data.amountGet, data.tokenGive, data.amountGive, data.expires, data.nonce, data.user, data.v, data.r, data.s, amountToTrade);
        withdraw(data.tokenGive, amountReceivedFromOrder);
        if(availableToSpend > amountSpentOnOrder){
            if(data.tokenGet == Utils.eth_address()){
                msg.sender.transfer(availableToSpend - amountSpentOnOrder);
            } else {
                ERC20SafeTransfer.safeTransfer(data.tokenGet, msg.sender, availableToSpend - amountSpentOnOrder);
            }
        }
        if(data.tokenGive == Utils.eth_address()){
            msg.sender.transfer(amountReceivedFromOrder);
        } else {
            ERC20SafeTransfer.safeTransfer(data.tokenGive, msg.sender, amountReceivedFromOrder);
        }
    }

    function deposit(
        address token,
        uint256 amount
    )
        internal
    {
        if(token == Utils.eth_address()){
            exchange.deposit.value(amount)();
        } else {
            exchange.depositToken(token, amount);
        }
    }

    function withdraw(
        address token,
        uint256 amount
    )
        internal
    {
        if(token == Utils.eth_address()){
            exchange.withdraw(amount);
        } else {
            exchange.withdrawToken(token, amount);
        }
    }
    

    /// @notice Subtract fee percentage from the amount give
    /// @param feePercentage the percentage fee to deduct
    /// @param  amount the amount that we should deduct from
    /// @return amountMinusFee the amount that would be spent on the order
    /// @return fee the amount that was received from this order
    function subtractFee(
        uint256 feePercentage,
        uint256 amount
    )
        internal
        pure
        returns (uint256 amountMinusFee, uint256 fee)
    {
        fee = SafeMath.sub(amount, getPartialAmount(amount, SafeMath.add(feePercentage, 1 ether), 1 ether ));
        amountMinusFee = SafeMath.sub(amount, fee);
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
    )
        internal
        pure
        returns (uint256)
    {
        return SafeMath.div(SafeMath.mul(numerator, target), denominator);
    }

    /// @notice Gets the amount that Totle needs to give for this order
    /// @param data OrderData struct containing order values
    /// @return amountToGive amount taker needs to give in order to fill the order
    function getAvailableVolume(
        OrderData memory data
    )
        internal
        view
        returns (uint256 availableVolume)
    {
        return exchange.availableVolume(
            data.tokenGet,
            data.amountGet,
            data.tokenGive,
            data.amountGive,
            data.expires,
            data.nonce,
            data.user,
            data.v,
            data.r,
            data.s
        );
    }

    /// @notice Add fee percentage from the amount give
    /// @param feePercentage the percentage fee to deduct
    /// @param  amount the amount that we should deduct from
    /// @return fee the amount that was received from this order
    function addFee(
        uint256 feePercentage,
        uint256 amount
    )
        internal
        pure
        returns (uint256 total)
    {
        return SafeMath.add(SafeMath.div(SafeMath.mul(amount, feePercentage), 1 ether), amount);
    }

    function approve(
        address token
    )
        internal 
    {
        if(token != Utils.eth_address()){
            approveAddress(address(exchange), token);
        }
    }

    /// @notice payable fallback to block EOA sending eth
    /// @dev this should fail if an EOA (or contract with 0 bytecode size) tries to send ETH to this contract
    function() external payable {
        // Check in here that the sender is a contract! (to stop accidents)
        uint256 size;
        address sender = msg.sender;
        assembly {
            size := extcodesize(sender)
        }
        require(size > 0);
    }
}
