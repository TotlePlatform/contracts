pragma solidity 0.4.25;
pragma experimental ABIEncoderV2;

import "../lib/SafeMath.sol";
import "../lib/Math.sol";
import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "../lib/ErrorReporter.sol";
import "./ExchangeHandler.sol";
import "./SelectorProvider.sol";

contract Ethex {
    function takeSellOrder(address token, uint256 tokenAmount, uint256 weiAmount, address seller) external payable;
    function takeBuyOrder(address token, uint256 tokenAmount, uint256 weiAmount, uint256 totalTokens, address buyer) external;
    function sellOrderBalances(bytes32 orderHash) external constant returns (uint256); //Returns number of tokens - e.g. available maker tokens
    function buyOrderBalances(bytes32 orderHash) external constant returns (uint256); //Returns number of eth - e.g. available maker's eth
    function makeFee() external constant returns (uint256);
    function takeFee() external constant returns (uint256);
    function feeFromTotalCostForAccount(uint256 totalCost, uint256 feeAmount, address account) external constant returns (uint256);
    function calculateFeeForAccount(uint256 cost, uint256 feeAmount, address account) public constant returns (uint256);
}

/// @title EthexHandler
/// @notice Handles the all EtherDelta trades for the primary contract
contract EthexHandler is ExchangeHandler, AllowanceSetter {

    /*
    *   State Variables
    */

    Ethex public exchange;

    /*
    *   Types
    */

    struct OrderData {
        address token;       //Token address
        uint256 tokenAmount; //Order's token amount
        uint256 weiAmount;   //Order's wei amount
        address maker;       //Person that created the order
        bool isSell;         //True if sell order, false if buy order - This is from the Ethex order perspective. E.g. An Ethex sell order is a Totle buy order, so this is True.
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
        exchange = Ethex(_exchange);
    }

    /*
    *   Public functions
    */

    /// @notice Gets the amount that Totle needs to give for this order
    /// @dev Uses the `onlyTotle` modifier with public visibility as this function
    /// should only be called from functions which are inherited from the ExchangeHandler
    /// base contract
    /// @param order OrderData struct containing order values
    /// @return amountToGive amount taker needs to give in order to fill the order
    function getAmountToGive(
        OrderData order
    )
        public
        view
        onlyTotle
        returns (uint256 amountToGive)
    {
        bytes32 orderHash = hashOrder(order);
        uint256 makeFee = exchange.makeFee();
        uint256 takeFee = exchange.takeFee();
        uint256 ethVolumeAvailable;
        if(order.isSell){
            uint256 tokenVolumeAvailable = Math.min(exchange.sellOrderBalances(orderHash), order.tokenAmount);
            ethVolumeAvailable = SafeMath.div(SafeMath.mul(tokenVolumeAvailable, order.weiAmount), order.tokenAmount);
            amountToGive = SafeMath.add(ethVolumeAvailable, feeFromTotalCost(ethVolumeAvailable, takeFee));
        } else {
            ethVolumeAvailable = Math.min(removeFee(exchange.buyOrderBalances(orderHash), makeFee), order.weiAmount);
            amountToGive = SafeMath.div(SafeMath.mul(ethVolumeAvailable, order.tokenAmount), order.weiAmount);
        }
        /* logger.log("Remaining volume from Ethex", amountToGive); */
    }

    /// @notice Perform exchange-specific checks on the given order
    /// @dev Uses the `onlyTotle` modifier with public visibility as this function
    /// should only be called from functions which are inherited from the ExchangeHandler
    /// base contract.
    /// This should be called to check for payload errors.
    /// @param order OrderData struct containing order values
    /// @return checksPassed value representing pass or fail
    function staticExchangeChecks(
        OrderData order
    )
        public
        view
        onlyTotle
        returns (bool checksPassed)
    {
        //Nothing to check
        return true;
    }

    /// @notice Perform a buy order at the exchange
    /// @dev Uses the `onlyTotle` modifier with public visibility as this function
    /// should only be called from functions which are inherited from the ExchangeHandler
    /// base contract
    /// @param order OrderData struct containing order values
    /// @param  amountToGiveForOrder amount that should be spent on this order
    /// @return amountSpentOnOrder the amount that would be spent on the order
    /// @return amountReceivedFromOrder the amount that was received from this order
    function performBuyOrder(
        OrderData order,
        uint256 amountToGiveForOrder
    )
        public
        payable
        onlyTotle
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        uint256 takeFee = exchange.takeFee();
        amountSpentOnOrder = amountToGiveForOrder;
        uint256 amountSpentMinusFee = SafeMath.sub(amountSpentOnOrder, exchange.feeFromTotalCostForAccount(amountSpentOnOrder, takeFee, address(this)));
        amountReceivedFromOrder = SafeMath.div(SafeMath.mul(amountSpentMinusFee, order.tokenAmount), order.weiAmount);
        exchange.takeSellOrder.value(amountToGiveForOrder)(order.token, order.tokenAmount, order.weiAmount, order.maker);
        if (!ERC20SafeTransfer.safeTransfer(order.token, msg.sender, amountReceivedFromOrder)) {
            errorReporter.revertTx("Unable to transfer bought tokens to primary");
        }
    }

    /// @notice Perform a sell order at the exchange
    /// @dev Uses the `onlyTotle` modifier with public visibility as this function
    /// should only be called from functions which are inherited from the ExchangeHandler
    /// base contract
    /// @param order OrderData struct containing order values
    /// @param  amountToGiveForOrder amount that should be spent on this order
    /// @return amountSpentOnOrder the amount that would be spent on the order
    /// @return amountReceivedFromOrder the amount that was received from this order
    function performSellOrder(
        OrderData order,
        uint256 amountToGiveForOrder
    )
        public
        onlyTotle
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        approveAddress(address(exchange), order.token);
        uint256 takeFee = exchange.takeFee();
        amountSpentOnOrder = amountToGiveForOrder;
        uint256 ethAmount = SafeMath.div(SafeMath.mul(amountSpentOnOrder, order.weiAmount), order.tokenAmount);
        amountReceivedFromOrder = SafeMath.sub(ethAmount, exchange.calculateFeeForAccount(ethAmount, takeFee, address(this)));
        exchange.takeBuyOrder(order.token, order.tokenAmount, order.weiAmount, amountSpentOnOrder, order.maker);
        msg.sender.transfer(amountReceivedFromOrder);
    }


    function hashOrder(OrderData order) internal pure returns (bytes32){
        return sha256(order.token, order.tokenAmount, order.weiAmount, order.maker);
    }

    function removeFee(uint256 cost, uint256 feeAmount) internal pure returns (uint256) {
        return SafeMath.div(SafeMath.mul(cost, 1e18), SafeMath.add(1e18, feeAmount));
    }

    function addFee(uint256 cost, uint256 feeAmount) internal pure returns (uint256) {
        return SafeMath.div(SafeMath.mul(cost, 1e18), SafeMath.sub(1e18, feeAmount));
    }

    function feeFromTotalCost(uint256 totalCost, uint256 feeAmount) public constant returns (uint256) {

        uint256 cost = SafeMath.mul(totalCost, (1 ether)) / SafeMath.add((1 ether), feeAmount);

        // Calculate ceil(cost).
        uint256 remainder = SafeMath.mul(totalCost, (1 ether)) % SafeMath.add((1 ether), feeAmount);
        if (remainder != 0) {
            cost = SafeMath.add(cost, 1);
        }

        uint256 fee = SafeMath.sub(totalCost, cost);
        return fee;
    }

    function getSelector(bytes4 genericSelector) public pure returns (bytes4) {
        if (genericSelector == getAmountToGiveSelector) {
            return bytes4(keccak256("getAmountToGive((address,uint256,uint256,address,bool))"));
        } else if (genericSelector == staticExchangeChecksSelector) {
            return bytes4(keccak256("staticExchangeChecks((address,uint256,uint256,address,bool))"));
        } else if (genericSelector == performBuyOrderSelector) {
            return bytes4(keccak256("performBuyOrder((address,uint256,uint256,address,bool),uint256)"));
        } else if (genericSelector == performSellOrderSelector) {
            return bytes4(keccak256("performSellOrder((address,uint256,uint256,address,bool),uint256)"));
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
