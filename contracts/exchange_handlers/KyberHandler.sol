pragma solidity 0.4.25;
pragma experimental ABIEncoderV2;

import "../lib/ERC20.sol";
import "../lib/SafeMath.sol";
import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "../lib/ErrorReporter.sol";
import "./ExchangeHandler.sol";

interface ENSResolver {
    function getKyberNetworkAddress() external view returns (address);
}

interface Kyber {

    function trade(ERC20 src, uint srcAmount, ERC20 dest, address destAddress, uint maxDestAmount, uint minConversionRate, address walletId) external payable returns (uint);
    function maxGasPrice() external view returns(uint);
    function getExpectedRate(ERC20 source, ERC20 dest, uint srcQty) external view returns (uint expectedPrice, uint slippagePrice);
}

/// @title KyberSelectorProvider
/// @notice Provides this exchange implementation with correctly formatted function selectors
contract KyberSelectorProvider is SelectorProvider {
    function getSelector(bytes4 genericSelector) public pure returns (bytes4) {
        if (genericSelector == getAmountToGive) {
            return bytes4(keccak256("getAmountToGive((address,address,uint256,uint256,address))"));
        } else if (genericSelector == staticExchangeChecks) {
            return bytes4(keccak256("staticExchangeChecks((address,address,uint256,uint256,address))"));
        } else if (genericSelector == performBuyOrder) {
            return bytes4(keccak256("performBuyOrder((address,address,uint256,uint256,address),uint256)"));
        } else if (genericSelector == performSellOrder) {
            return bytes4(keccak256("performSellOrder((address,address,uint256,uint256,address),uint256)"));
        } else {
            return bytes4(0x0);
        }
    }
}

/// @title Interface for all exchange handler contracts
contract KyberHandler is ExchangeHandler, AllowanceSetter {
    /*
    *   State Variables
    */
    ENSResolver public ensResolver;
    address ETH_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    /*
    *   Types
    */

    struct OrderData {
        address tokenFrom;
        address tokenTo;
        uint256 amountToGive;
        uint256 minConversionRate;
        address walletId;
    }


    /// @notice Constructor
    /// @param _ensResolver Address of the ENS resolver
    /// @param _selectorProvider the provider for this exchanges function selectors
    /// @param _totlePrimary the address of the totlePrimary contract
    constructor(
        address _ensResolver,
        address _selectorProvider,
        address _totlePrimary,
        address errorReporter
        /* ,address logger */
    )
        ExchangeHandler(_selectorProvider, _totlePrimary, errorReporter/*,logger*/)
        public
    {
        ensResolver = ENSResolver(_ensResolver);
    }

    /*
    *   Internal functions
    */


    /// @notice Gets the amount that Totle needs to give for this order
    /// @param data OrderData struct containing order values
    /// @return amountToGive amount taker needs to give in order to fill the order
    function getAmountToGive(
        OrderData data
    )
        public
        view
        whenNotPaused
        onlySelf
        returns (uint256 amountToGive)
    {
        // Adds the exchange fee onto the available amount
        amountToGive = data.amountToGive;
    }



    /// @notice Perform exchange-specific checks on the given order
    /// @dev This should be called to check for payload errors
    /// @param data OrderData struct containing order values
    /// @return checksPassed value representing pass or fail
    function staticExchangeChecks(
        OrderData data
    )
        public
        view
        whenNotPaused
        onlySelf
        returns (bool checksPassed)
    {
        uint256 maxGasPrice = resolveExchangeAddress().maxGasPrice();
        /* logger.log("Checking gas price arg2: tx.gasprice, arg3: maxGasPrice", tx.gasprice, maxGasPrice); */
        return (maxGasPrice >= tx.gasprice);
    }

    /// @dev Perform a buy order at the exchange
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
        whenNotPaused
        onlySelf
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        amountSpentOnOrder = amountToGiveForOrder;
        amountReceivedFromOrder = performTrade(data.tokenFrom, amountToGiveForOrder, data.tokenTo, data.minConversionRate);
        /* logger.log("Performing Kyber buy order arg2: amountSpentOnOrder, arg3: amountReceivedFromOrder", amountSpentOnOrder, amountReceivedFromOrder); */
    }

    /// @dev Perform a sell order at the exchange
    /// @param data OrderData struct containing order values
    /// @param  amountToGiveForOrder amount that should be spent on this order
    /// @return amountSpentOnOrder the amount that would be spent on the order
    /// @return amountReceivedFromOrder the amount that was received from this order
    function performSellOrder(
        OrderData data,
        uint256 amountToGiveForOrder
    )
        public
        whenNotPaused
        onlySelf
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        approveAddress(address(resolveExchangeAddress()), data.tokenFrom);
        amountSpentOnOrder = amountToGiveForOrder;
        amountReceivedFromOrder = performTrade(data.tokenFrom, amountToGiveForOrder, data.tokenTo, data.minConversionRate);
        /* logger.log("Performing Kyber sell order arg2: amountSpentOnOrder, arg3: amountReceivedFromOrder",amountSpentOnOrder,amountReceivedFromOrder); */
    }

    function performTrade(
        address tokenFrom,
        uint256 amountToGive,
        address tokenTo,
        uint256 minConversionRate
    )
         internal
         returns (uint256 amountReceivedFromOrder)
    {
        amountReceivedFromOrder = resolveExchangeAddress().trade.value(msg.value)(
            ERC20(tokenFrom),
            amountToGive,
            ERC20(tokenTo),
            totlePrimary,
            Utils.max_uint(),
            minConversionRate,
            0x0
        );

        // If Kyber has sent us back some excess ether
        // TODO: If ether gets accidentally trapped in this contract by some other transaction,
        //       this function will send it back to the primary in the subsequent order.
        //       Change code to only return back what's left over from *this* transaction.
        if(address(this).balance > 0) {
            /* logger.log("Got excess ether back from Kyber arg2: address(this).balance",address(this).balance); */
            totlePrimary.transfer(address(this).balance);
        }
    }

    function resolveExchangeAddress()
        internal
        view
        returns (Kyber)
    {
        return Kyber(ensResolver.getKyberNetworkAddress());
    }

    /// @notice payable fallback to block EOA sending eth
    /// @dev this should fail if an EOA (or contract with 0 bytecode size) tries to send ETH to this contract
    function() public payable {
        // Check in here that the sender is a contract! (to stop accidents)
        uint256 size;
        address sender = msg.sender;
        assembly {
            size := extcodesize(sender)
        }
        require(size > 0);
    }
}
