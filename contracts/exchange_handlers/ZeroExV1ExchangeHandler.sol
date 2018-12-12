pragma solidity 0.4.25;
pragma experimental ABIEncoderV2;

import "../lib/ERC20.sol";
import "../lib/SafeMath.sol";
import "../lib/Math.sol";
import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "./ExchangeHandler.sol";
import "./SelectorProvider.sol";

interface WETH {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface ZeroExExchange {
    function fillOrder(
        address[5] orderAddresses,
        uint[6] orderValues,
        uint fillTakerTokenAmount,
        bool shouldThrowOnInsufficientBalanceOrAllowance,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint filledTakerTokenAmount);

    function TOKEN_TRANSFER_PROXY_CONTRACT() external constant returns (address);
    function ZRX_TOKEN_CONTRACT() external constant returns (address);

    function getOrderHash(address[5] orderAddresses, uint[6] orderValues) external constant returns (bytes32);

    function getUnavailableTakerTokenAmount(bytes32 orderHash) external constant returns (uint);
}

/// @title ZeroExV1ExchangeSelectorProvider
/// @notice Provides this exchange implementation with correctly formatted function selectors
contract ZeroExV1ExchangeSelectorProvider is SelectorProvider {
    function getSelector(bytes4 genericSelector) public pure returns (bytes4) {
        if (genericSelector == getAmountToGive) {
            return bytes4(keccak256("getAmountToGive_((address,address,address,address,address,uint256,uint256,uint256,uint256,uint256,uint256,uint8,bytes32,bytes32))"));
        } else if (genericSelector == staticExchangeChecks) {
            return bytes4(keccak256("staticExchangeChecks_((address,address,address,address,address,uint256,uint256,uint256,uint256,uint256,uint256,uint8,bytes32,bytes32))"));
        } else if (genericSelector == performBuyOrder) {
            return bytes4(keccak256("performBuyOrder_((address,address,address,address,address,uint256,uint256,uint256,uint256,uint256,uint256,uint8,bytes32,bytes32),uint256)"));
        } else if (genericSelector == performSellOrder) {
            return bytes4(keccak256("performSellOrder_((address,address,address,address,address,uint256,uint256,uint256,uint256,uint256,uint256,uint8,bytes32,bytes32),uint256)"));
        } else {
            return bytes4(0x0);
        }
    }
}

// (address,address,address,address,address,uint256,uint256,uint256,uint256,uint256,uint256,uint8,bytes32,bytes32)

/// @title ZeroExV1ExchangeHandler
/// @notice Handles the all ZeroExExchange trades for the primary contract
contract ZeroExV1ExchangeHandler is ExchangeHandler, AllowanceSetter  {

    /*
    *   State Variables
    */

    ZeroExExchange public exchange;
    address public ZRX_TOKEN_CONTRACT;
    address public TOKEN_TRANSFER_PROXY_CONTRACT;
    WETH weth;

    /*
    *   Types
    */

    /// @notice Constructor
    /// @param _exchange Address of the ZeroExExchange exchange
    /// @param selectorProvider the provider for this exchanges function selectors
    /// @param totlePrimary the address of the totlePrimary contract
    /// @param _weth the address of the wrapped Ether contract
    constructor(
        address _exchange,
        address selectorProvider,
        address totlePrimary,
        address _weth,
        address errorReporter
        /* ,address logger */
    )
        ExchangeHandler(selectorProvider, totlePrimary, errorReporter/*, logger*/)
        public
    {
        require(_exchange != address(0x0));
        exchange = ZeroExExchange(_exchange);
        ZRX_TOKEN_CONTRACT = exchange.ZRX_TOKEN_CONTRACT();
        TOKEN_TRANSFER_PROXY_CONTRACT = exchange.TOKEN_TRANSFER_PROXY_CONTRACT();
        weth = WETH(_weth);
    }

    struct OrderData {
        address maker;
        address taker;
        address makerToken;
        address takerToken;
        address feeRecipient;
        uint makerTokenAmount;
        uint takerTokenAmount;
        uint makerFee;
        uint takerFee;
        uint expirationTimestampInSec;
        uint salt;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    /*
    *   Public functions
    */



    /*
    *   Internal functions
    */

    /// @notice Gets the amount that Totle needs to give for this order
    /// @param data OrderData struct containing order values
    /// @return amountToGive amount taker needs to give in order to fill the order
    function getAmountToGive_(
        OrderData data
    )
      public
      view
      onlySelf
      returns (uint256 amountToGive)
    {
        bytes32 orderHash = exchange.getOrderHash(getAddresses(data), getValues(data));
        uint256 takerTokenFilledAmount = exchange.getUnavailableTakerTokenAmount(orderHash);
        uint makerTokenAvailable = getTokenAvailable(data.makerToken, data.maker);
        uint feeAssetAvailable = getTokenAvailable(ZRX_TOKEN_CONTRACT, data.maker);

        return Math.min(Math.min(
            getPartialAmount(makerTokenAvailable, data.makerTokenAmount, data.takerTokenAmount),
            getPartialAmount(feeAssetAvailable, data.makerFee, data.takerTokenAmount)),
            SafeMath.sub(data.takerTokenAmount, takerTokenFilledAmount)
        );
    }

    function getOrderHash(address[5] addresses, uint256[6] values) public view returns (bytes32) {
        return exchange.getOrderHash(addresses, values);
    }

    function getTokenAvailable(address tokenAddress, address account) internal view returns (uint){
        ERC20 token = ERC20(tokenAddress);
        return Math.min(token.balanceOf(account), token.allowance(account, TOKEN_TRANSFER_PROXY_CONTRACT));
    }

    /// @notice Perform exchange-specific checks on the given order
    /// @dev This should be called to check for payload errors
    /// @param data OrderData struct containing order values
    /// @return checksPassed value representing pass or fail
    function staticExchangeChecks_(
        OrderData data
    )
        public
        view
        onlySelf
        returns (bool checksPassed)
    {

        // Make sure that:
        //  The order is not expired
        //  The taker does not have to pay a fee (we don't support fees yet)
        //  We are permitted to take this order
        // TODO: Should we check signatures here?
        return (block.timestamp <= data.expirationTimestampInSec &&
                data.takerFee == 0 &&
                (data.taker == address(0x0) || data.taker == address(this))
        );
    }

    /// @notice Perform a buy order at the exchange
    /// @param data OrderData struct containing order values
    /// @param  amountToGiveForOrder amount that should be spent on this order
    /// @return amountSpentOnOrder the amount that would be spent on the order
    /// @return amountReceivedFromOrder the amount that was received from this order
    function performBuyOrder_(
        OrderData data,
        uint256 amountToGiveForOrder
    )
        public
        payable
        onlySelf
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        require(msg.value == amountToGiveForOrder);
        approveAddress(TOKEN_TRANSFER_PROXY_CONTRACT, data.takerToken);

        weth.deposit.value(amountToGiveForOrder)();

        uint256 filledAmount = exchange.fillOrder(
            getAddresses(data),
            getValues(data),
            amountToGiveForOrder,
            true,
            data.v,
            data.r,
            data.s
        );
        amountReceivedFromOrder = getPartialAmount(amountToGiveForOrder, data.takerTokenAmount, data.makerTokenAmount);
        ERC20 makerToken = ERC20(data.makerToken);
        require(makerToken.transfer(totlePrimary, amountReceivedFromOrder));

        amountSpentOnOrder = amountToGiveForOrder;
    }

    /// @notice Perform a sell order at the exchange
    /// @param data OrderData struct containing order values
    /// @param  amountToGiveForOrder amount that should be spent on this order
    /// @return amountSpentOnOrder the amount that would be spent on the order
    /// @return amountReceivedFromOrder the amount that was received from this order
    function performSellOrder_(
        OrderData data,
        uint256 amountToGiveForOrder
    )
        public
        onlySelf
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        approveAddress(TOKEN_TRANSFER_PROXY_CONTRACT, data.takerToken);


        uint256 filledAmount = exchange.fillOrder(
            getAddresses(data),
            getValues(data),
            amountToGiveForOrder,
            false,
            data.v,
            data.r,
            data.s
        );
        amountReceivedFromOrder = getPartialAmount(amountToGiveForOrder, data.takerTokenAmount, data.makerTokenAmount);
        weth.withdraw(amountReceivedFromOrder);
        totlePrimary.transfer(amountReceivedFromOrder);

        amountSpentOnOrder = amountToGiveForOrder;
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

    function getAddresses(OrderData order) internal pure returns (address[5] addresses) {
        addresses[0] = order.maker;
        addresses[1] = order.taker;
        addresses[2] = order.makerToken;
        addresses[3] = order.takerToken;
        addresses[4] = order.feeRecipient;
    }

    function getValues(OrderData order) internal pure returns (uint256[6] numbers) {
        numbers[0] = order.makerTokenAmount;
        numbers[1] = order.takerTokenAmount;
        numbers[2] = order.makerFee;
        numbers[3] = order.takerFee;
        numbers[4] = order.expirationTimestampInSec;
        numbers[5] = order.salt;
    }

    /*
    *   Payable fallback function
    */

    /// @notice payable fallback to allow the exchange to return ether directly to this contract
    /// @dev note that only the exchange should be able to send ether to this contract
    function() public payable {
        require(msg.sender == address(weth) || msg.sender == address(totlePrimary));
    }
}
