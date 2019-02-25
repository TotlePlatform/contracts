pragma solidity 0.4.25;
pragma experimental ABIEncoderV2;

import "../lib/SafeMath.sol";
import "../lib/Math.sol";
import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "../lib/ErrorReporter.sol";
import "./ExchangeHandler.sol";
import "./SelectorProvider.sol";

interface EtherDelta {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function depositToken(address token, uint256 amount) external;
    function withdrawToken(address token, uint256 amount) external;
    function trade(address tokenGet, uint256 amountGet, address tokenGive, uint256 amountGive, uint256 expires, uint256 nonce, address user, uint8 v, bytes32 r, bytes32 s, uint256 amount) external;
    function availableVolume(address tokenGet, uint256 amountGet, address tokenGive, uint256 amountGive, uint256 expires, uint256 nonce, address user, uint8 v, bytes32 r, bytes32 s) external view returns (uint256);
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
        uint256 exchangeFee;
    }

    /// @notice Constructor
    /// @param _exchange Address of the EtherDelta exchange
    /// @param totlePrimary the address of the totlePrimary contract
    /// @param errorReporter the address of the error reporter contract
    constructor(
        address _exchange,
        address totlePrimary,
        address errorReporter
        /* ,address logger */
    )
        ExchangeHandler(totlePrimary, errorReporter/*, logger*/)
        public
    {
        require(_exchange != address(0x0));
        exchange = EtherDelta(_exchange);
    }

    /*
    *   Public functions
    */

    /// @notice Gets the amount that Totle needs to give for this order
    /// @dev Uses the `onlyTotle` modifier with public visibility as this function
    /// should only be called from functions which are inherited from the ExchangeHandler
    /// base contract
    /// @param data OrderData struct containing order values
    /// @return amountToGive amount taker needs to give in order to fill the order
    function getAmountToGive(
        OrderData data
    )
        public
        view
        onlyTotle
        returns (uint256 amountToGive)
    {
        uint256 availableVolume = exchange.availableVolume(
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
        /* logger.log("Getting available volume from Etherdelta", availableVolume); */
        // Adds the exchange fee onto the available amount
        amountToGive = getPartialAmount(availableVolume, SafeMath.sub(1 ether, data.exchangeFee), 1 ether);
        /* logger.log("Removing fee from amountToGive", amountToGive); */
    }

    /// @notice Perform exchange-specific checks on the given order
    /// @dev Uses the `onlyTotle` modifier with public visibility as this function
    /// should only be called from functions which are inherited from the ExchangeHandler
    /// base contract.
    /// This should be called to check for payload errors.
    /// @param data OrderData struct containing order values
    /// @return checksPassed value representing pass or fail
    function staticExchangeChecks(
        OrderData data
    )
        public
        view
        onlyTotle
        returns (bool checksPassed)
    {
        /* logger.log(block.number <= data.expires ? "Order isn't expired" : "Order is expired"); */
        // Only one thing to check here
        return block.number <= data.expires; // TODO - check if this is < or <=
    }

    /// @notice Perform a buy order at the exchange
    /// @dev Uses the `onlyTotle` modifier with public visibility as this function
    /// should only be called from functions which are inherited from the ExchangeHandler
    /// base contract
    /// @param data OrderData struct containing order values
    /// @param  amountToGiveForOrder amount that should be spent on this order
    /// @return amountSpentOnOrder the amount that would be spent on the order
    /// @return amountReceivedFromOrder the amount that was received from this order
    function performBuyOrder(
        OrderData data,
        uint256 amountToGiveForOrder
    )
        public
        payable
        onlyTotle
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        if (msg.value != amountToGiveForOrder) {
            errorReporter.revertTx("msg.value != amountToGiveForOrder");
        }
        /* logger.log("Depositing eth to Etherdelta arg2: amountToGive, arg3: ethBalance", amountToGiveForOrder, address(this).balance); */
        exchange.deposit.value(amountToGiveForOrder)();

        uint256 amountToTrade;
        uint256 fee;

        (amountToTrade, fee) = substractFee(data.exchangeFee, amountToGiveForOrder);
        /* logger.log("Removing fee from amountToGiveForOrder arg2: amountToGiveForOrder, arg3: amountToTrade, arg4: fee", amountToGiveForOrder, amountToTrade, fee); */
        trade(data, amountToTrade);

        amountSpentOnOrder = amountToGiveForOrder;
        amountReceivedFromOrder = getPartialAmount(data.amountGive, data.amountGet, amountToTrade);
        /* logger.log("Withdrawing tokens from EtherDelta arg2: amountReceivedFromOrder, arg3: amountSpentOnOrder", amountReceivedFromOrder, amountSpentOnOrder); */
        exchange.withdrawToken(data.tokenGive, amountReceivedFromOrder);

        if (!ERC20SafeTransfer.safeTransfer(data.tokenGive, msg.sender, amountReceivedFromOrder)) {
            errorReporter.revertTx("Unable to transfer bought tokens to primary");
        }
    }

    /// @notice Perform a sell order at the exchange
    /// @dev Uses the `onlyTotle` modifier with public visibility as this function
    /// should only be called from functions which are inherited from the ExchangeHandler
    /// base contract
    /// @param data OrderData struct containing order values
    /// @param  amountToGiveForOrder amount that should be spent on this order
    /// @return amountSpentOnOrder the amount that would be spent on the order
    /// @return amountReceivedFromOrder the amount that was received from this order
    function performSellOrder(
        OrderData data,
        uint256 amountToGiveForOrder
    )
        public
        onlyTotle
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        approveAddress(address(exchange), data.tokenGet);
        /* logger.log("Depositing tokens to EtherDelta arg2: amountToGiveForOrder", amountToGiveForOrder); */
        exchange.depositToken(data.tokenGet, amountToGiveForOrder);

        uint256 amountToTrade;
        uint256 fee;

        (amountToTrade, fee) = substractFee(data.exchangeFee, amountToGiveForOrder);
        /* logger.log("arg2: amountToTrade, arg3: fee", amountToTrade, fee); */

        trade(data, amountToTrade);

        amountSpentOnOrder = amountToGiveForOrder;
        amountReceivedFromOrder = getPartialAmount(data.amountGive, data.amountGet, amountToTrade);

        exchange.withdraw(amountReceivedFromOrder);
        /* logger.log("Withdrawing ether arg2: amountReceived", amountReceivedFromOrder); */
        msg.sender.transfer(amountReceivedFromOrder);
    }

    /*
    *   Internal functions
    */

    /// @notice Performs the trade at the exchange
    /// @dev It was necessary to separate this into a function due to limited stack space
    /// @param data OrderData struct containing order values
    /// @param amountToTrade amount that should be spent on this order
    function trade(
        OrderData data,
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

    /// @notice Subtract fee percentage from the amount give
    /// @param feePercentage the percentage fee to deduct
    /// @param  amount the amount that we should deduct from
    /// @return amountMinusFee the amount that would be spent on the order
    /// @return fee the amount that was received from this order
    function substractFee(
        uint256 feePercentage,
        uint256 amount
    )
        public
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

    function getSelector(bytes4 genericSelector) public pure returns (bytes4) {
        if (genericSelector == getAmountToGiveSelector) {
            return bytes4(keccak256("getAmountToGive((address,address,address,uint256,uint256,uint256,uint256,uint8,bytes32,bytes32,uint256))"));
        } else if (genericSelector == staticExchangeChecksSelector) {
            return bytes4(keccak256("staticExchangeChecks((address,address,address,uint256,uint256,uint256,uint256,uint8,bytes32,bytes32,uint256))"));
        } else if (genericSelector == performBuyOrderSelector) {
            return bytes4(keccak256("performBuyOrder((address,address,address,uint256,uint256,uint256,uint256,uint8,bytes32,bytes32,uint256),uint256)"));
        } else if (genericSelector == performSellOrderSelector) {
            return bytes4(keccak256("performSellOrder((address,address,address,uint256,uint256,uint256,uint256,uint8,bytes32,bytes32,uint256),uint256)"));
        } else {
            return bytes4(0x0);
        }
    }

    /*
    *   Payable fallback function
    */

    /// @notice payable fallback to allow the exchange to return ether directly to this contract
    /// @dev note that only the exchange should be able to send ether to this contract
    function() public payable {
        if (msg.sender != address(exchange)) {
            errorReporter.revertTx("An address other than the exchange cannot send ether to EDHandler fallback");
        }
    }
}
