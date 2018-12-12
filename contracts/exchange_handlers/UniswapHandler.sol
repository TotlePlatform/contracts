pragma solidity 0.4.25;
pragma experimental ABIEncoderV2;

import "../lib/ERC20.sol";
import "../lib/SafeMath.sol";
import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "../lib/ErrorReporter.sol";
import "./ExchangeHandler.sol";

interface UniswapExchange {

   //Trading
   function ethToTokenSwapInput(uint256 min_tokens, uint256 deadline) external payable returns (uint256);
   function tokenToEthSwapInput(uint256 tokens_sold, uint256 min_eth, uint256 deadline) external returns (uint256);

   function ethToTokenTransferInput(uint256 min_tokens, uint256 deadline, address recipient) external payable returns (uint256);
   function tokenToEthTransferInput(uint256 tokens_sold, uint256 min_eth, uint256 deadline, address recipient) external returns (uint256);

   // Get Price
   function getEthToTokenInputPrice(uint256 eth_sold) external constant returns (uint256);
   function getTokenToEthInputPrice(uint256 tokens_sold) external constant returns (uint256);

   function tokenAddress() external constant returns (address);
}

/// @title UniswapSelectorProvider
/// @notice Provides this exchange implementation with correctly formatted function selectors
contract UniswapSelectorProvider is SelectorProvider {
    function getSelector(bytes4 genericSelector) public pure returns (bytes4) {
        if (genericSelector == getAmountToGive) {
            return bytes4(keccak256("getAmountToGive((address,uint256))"));
        } else if (genericSelector == staticExchangeChecks) {
            return bytes4(keccak256("staticExchangeChecks((address,uint256))"));
        } else if (genericSelector == performBuyOrder) {
            return bytes4(keccak256("performBuyOrder((address,uint256),uint256)"));
        } else if (genericSelector == performSellOrder) {
            return bytes4(keccak256("performSellOrder((address,uint256),uint256)"));
        } else {
            return bytes4(0x0);
        }
    }
}

/// @title Handler for Uniswap exchange
contract UniswapHandler is ExchangeHandler, AllowanceSetter {
    /*
    *   Types
    */

    struct OrderData {
        address exchangeAddress;
        uint256 amountToGive;
    }


    /// @notice Constructor
    /// @param _selectorProvider the provider for this exchanges function selectors
    /// @param _totlePrimary the address of the totlePrimary contract
    /// @param errorReporter the address of of the errorReporter contract
    constructor(
        address _selectorProvider,
        address _totlePrimary,
        address errorReporter/*,
        address logger*/
    ) ExchangeHandler(_selectorProvider, _totlePrimary, errorReporter/*, logger*/) public {

    }

    /*
    *   Internal functions
    */


    /// @notice Gets the amount that TotlePrimary needs to give for this order
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
        return true;
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
        UniswapExchange ex = UniswapExchange(data.exchangeAddress);
        amountSpentOnOrder = amountToGiveForOrder;
        amountReceivedFromOrder = ex.ethToTokenTransferInput.value(amountToGiveForOrder)(1, block.timestamp+1, totlePrimary);
        /* logger.log("Performing Uniswap buy order arg2: amountSpentOnOrder, arg3: amountReceivedFromOrder", amountSpentOnOrder, amountReceivedFromOrder);  */

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
        UniswapExchange ex = UniswapExchange(data.exchangeAddress);
        approveAddress(data.exchangeAddress, ex.tokenAddress());
        amountSpentOnOrder = amountToGiveForOrder;
        amountReceivedFromOrder = ex.tokenToEthTransferInput(amountToGiveForOrder, 1, block.timestamp+1, totlePrimary);
        /* logger.log("Performing Uniswap sell order arg2: amountSpentOnOrder, arg3: amountReceivedFromOrder",amountSpentOnOrder,amountReceivedFromOrder); */
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
