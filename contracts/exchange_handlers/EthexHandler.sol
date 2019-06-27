pragma solidity 0.5.7;
pragma experimental ABIEncoderV2;

import "../lib/SafeMath.sol";
import "../lib/Math.sol";
import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "./ExchangeHandler.sol";

contract Ethex {
    function takeSellOrder(address token, uint256 tokenAmount, uint256 weiAmount, address seller) external payable;
    function takeBuyOrder(address token, uint256 tokenAmount, uint256 weiAmount, uint256 totalTokens, address buyer) external;
    function sellOrderBalances(bytes32 orderHash) external view returns (uint256); //Returns number of tokens - e.g. available maker tokens
    function buyOrderBalances(bytes32 orderHash) external view returns (uint256); //Returns number of eth - e.g. available maker's eth
    function makeFee() external view returns (uint256);
    function takeFee() external view returns (uint256);
    function feeFromTotalCostForAccount(uint256 totalCost, uint256 feeAmount, address account) external view returns (uint256);
    function calculateFeeForAccount(uint256 cost, uint256 feeAmount, address account) public view returns (uint256);
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
    constructor(
        address _exchange
    )
        public
    {
        exchange = Ethex(_exchange);
    }

    /*
    *   Public functions
    */

    /// @notice Gets the amount that Totle needs to give for this order
    /// @param order OrderData struct containing order values
    /// @return amountToGive amount taker needs to give in order to fill the order
    function getAmountToGive(
        OrderData memory order
    )
        public
        view
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


    /// @notice Perform a buy order at the exchange
    /// @param order OrderData struct containing order values
    /// @param  amountToGiveForOrder amount that should be spent on this order
    /// @return amountSpentOnOrder the amount that would be spent on the order
    /// @return amountReceivedFromOrder the amount that was received from this order
    function performBuyOrder(
        OrderData memory order,
        uint256 amountToGiveForOrder
    )
        public
        payable
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        uint256 takeFee = exchange.takeFee();
        amountSpentOnOrder = amountToGiveForOrder;
        uint256 amountSpentMinusFee = SafeMath.sub(amountSpentOnOrder, exchange.feeFromTotalCostForAccount(amountSpentOnOrder, takeFee, address(this)));
        amountReceivedFromOrder = SafeMath.div(SafeMath.mul(amountSpentMinusFee, order.tokenAmount), order.weiAmount);
        exchange.takeSellOrder.value(amountToGiveForOrder)(order.token, order.tokenAmount, order.weiAmount, order.maker);
        ERC20SafeTransfer.safeTransfer(order.token, msg.sender, amountReceivedFromOrder);
    }

    /// @notice Perform a sell order at the exchange
    /// @param order OrderData struct containing order values
    /// @param  amountToGiveForOrder amount that should be spent on this order
    /// @return amountSpentOnOrder the amount that would be spent on the order
    /// @return amountReceivedFromOrder the amount that was received from this order
    function performSellOrder(
        OrderData memory order,
        uint256 amountToGiveForOrder
    )
        public
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
        uint256 availableGiveVolume = Math.min(Math.min(getAmountToGive(data), availableToSpend), targetAmount);
        if(data.isSell){
            (amountSpentOnOrder, amountReceivedFromOrder) = performSellOrder(data, availableGiveVolume);
        } else {
            (amountSpentOnOrder, amountReceivedFromOrder) = performBuyOrder(data, availableGiveVolume);
        }
        if(amountSpentOnOrder < availableToSpend){
            if(data.isSell){
                ERC20SafeTransfer.safeTransfer(data.token, msg.sender, SafeMath.sub(availableToSpend, amountSpentOnOrder));
            } else {
                msg.sender.transfer(SafeMath.sub(availableToSpend, amountSpentOnOrder));
            }
        }
    }

    function hashOrder(OrderData memory order) internal pure returns (bytes32){
        return sha256(abi.encodePacked(order.token, order.tokenAmount, order.weiAmount, order.maker));
    }

    function removeFee(uint256 cost, uint256 feeAmount) internal pure returns (uint256) {
        return SafeMath.div(SafeMath.mul(cost, 1e18), SafeMath.add(1e18, feeAmount));
    }

    function addFee(uint256 cost, uint256 feeAmount) internal pure returns (uint256) {
        return SafeMath.div(SafeMath.mul(cost, 1e18), SafeMath.sub(1e18, feeAmount));
    }

    function feeFromTotalCost(uint256 totalCost, uint256 feeAmount) public view returns (uint256) {

        uint256 cost = SafeMath.mul(totalCost, (1 ether)) / SafeMath.add((1 ether), feeAmount);

        // Calculate ceil(cost).
        uint256 remainder = SafeMath.mul(totalCost, (1 ether)) % SafeMath.add((1 ether), feeAmount);
        if (remainder != 0) {
            cost = SafeMath.add(cost, 1);
        }

        uint256 fee = SafeMath.sub(totalCost, cost);
        return fee;
    }

    /*
    *   Payable fallback function
    */

    /// @notice payable fallback to allow the exchange to return ether directly to this contract
    /// @dev note that only the exchange should be able to send ether to this contract
    function() external payable {
        require(msg.sender == address(exchange), "An address other than the exchange cannot send ether to EDHandler fallback");
    }
}
