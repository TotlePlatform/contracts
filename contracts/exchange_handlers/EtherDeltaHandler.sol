pragma solidity 0.5.7;
pragma experimental ABIEncoderV2;

import "../lib/SafeMath.sol";
import "../lib/Math.sol";
import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "./ExchangeHandler.sol";

interface EtherDelta {
   //Balance deposit/withdraw functions
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function depositToken(address token, uint256 amount) external;
    function withdrawToken(address token, uint256 amount) external;

    //Trading
    function trade(address tokenGet, uint256 amountGet, address tokenGive, uint256 amountGive, uint256 expires, uint256 nonce, address user, uint8 v, bytes32 r, bytes32 s, uint256 amount) external;

    function availableVolume(address tokenGet, uint256 amountGet, address tokenGive, uint256 amountGive, uint256 expires, uint256 nonce, address user, uint8 v, bytes32 r, bytes32 s) external view returns (uint256);
    function feeTake() external returns (uint256);
}

/// @title EtherDeltaHandler
/// @notice Handles the all EtherDelta trades for the primary contract
contract EtherDeltaHandler is ExchangeHandler, AllowanceSetter {

    /*
    *   State Variables
    */

    EtherDelta public exchange;

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
    /// @param _exchange Address of the EtherDelta exchange
    constructor(
        address _exchange
        /* ,address logger */
    )
        public
    {
        exchange = EtherDelta(_exchange);
    }

    /*
    *   Public functions
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
        if(!staticExchangeChecks(data)){
            if(data.tokenGet == Utils.eth_address()){
                msg.sender.transfer(availableToSpend);
            } else {
                ERC20SafeTransfer.safeTransfer(data.tokenGive, msg.sender, availableToSpend);
            }
        }
        uint256 feePercentage = exchange.feeTake();
        approve(data.tokenGet);
        amountSpentOnOrder = Math.min(Math.min(availableToSpend, targetAmount), addFee(feePercentage, getAvailableVolume(data)));
        uint256 amountToTrade;
        uint256 fee;
        (amountToTrade, fee) = subtractFee(feePercentage, amountSpentOnOrder);
        amountReceivedFromOrder = getPartialAmount(data.amountGive, data.amountGet, amountToTrade);

        deposit(data.tokenGet, amountSpentOnOrder);
        trade(data, amountToTrade);
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


    /*
    *   Internal functions
    */

    /// @notice Performs the trade at the exchange
    /// @dev It was necessary to separate this into a function due to limited stack space
    /// @param data OrderData struct containing order values
    /// @param amountToTrade amount that should be spent on this order
    function trade(
        OrderData memory data,
        uint256 amountToTrade
    )
        internal
    {
        exchange.trade(
            data.tokenGet,
            data.amountGet,
            data.tokenGive,
            data.amountGive,
            data.expires,
            data.nonce,
            data.user,
            data.v,
            data.r,
            data.s,
            amountToTrade
        );
    }

    /// @notice Gets the amount that Totle needs to give for this order
    /// @dev Uses the `onlyTotle` modifier with public visibility as this function
    /// should only be called from functions which are inherited from the ExchangeHandler
    /// base contract
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

    /// @notice Perform exchange-specific checks on the given order
    /// @dev Uses the `onlyTotle` modifier with public visibility as this function
    /// should only be called from functions which are inherited from the ExchangeHandler
    /// base contract.
    /// This should be called to check for payload errors.
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

    /*
    *   Payable fallback function
    */

    /// @notice payable fallback to allow the exchange to return ether directly to this contract
    /// @dev note that only the exchange should be able to send ether to this contract
    function() external payable {
        revert("An address other than the exchange cannot send ether to EDHandler fallback");
    }
}
