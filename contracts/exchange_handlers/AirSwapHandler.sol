pragma solidity 0.4.25;
pragma experimental ABIEncoderV2;

import "../lib/AllowanceSetter.sol";
import "../lib/ERC20SafeTransfer.sol";
import "../lib/ErrorReporter.sol";
/* import "../lib/Logger.sol"; */
import "../lib/Math.sol";
import "../lib/SafeMath.sol";
import "../lib/Utils.sol";
import "../lib/WETH.sol";
import "./ExchangeHandler.sol";
import "./SelectorProvider.sol";

/// @title AirSwap
/// @notice Exchange contract interface
interface AirSwap {
    /// @dev Mapping of order hash to bool (true = already filled).
    function fills(bytes32 hash) external view returns (bool);

    /// @notice Fills an order by transferring tokens between (maker or escrow) and taker
    function fill(
        address makerAddress,
        uint makerAmount,
        address makerToken,
        address takerAddress,
        uint takerAmount,
        address takerToken,
        uint256 expiration,
        uint256 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable;
}

/// @title AirSwapSelectorProvider
/// @notice Provides this exchange implementation with correctly formatted function selectors
contract AirSwapSelectorProvider is SelectorProvider {
    function getSelector(bytes4 genericSelector) public pure returns (bytes4) {
        if (genericSelector == getAmountToGive) {
            return bytes4(keccak256("getAmountToGive((address,address,address,address,uint256,uint256,uint256,uint256,uint8,bytes32,bytes32))"));
        } else if (genericSelector == staticExchangeChecks) {
            return bytes4(keccak256("staticExchangeChecks((address,address,address,address,uint256,uint256,uint256,uint256,uint8,bytes32,bytes32))"));
        } else if (genericSelector == performBuyOrder) {
            return bytes4(keccak256("performBuyOrder((address,address,address,address,uint256,uint256,uint256,uint256,uint8,bytes32,bytes32),uint256)"));
        } else if (genericSelector == performSellOrder) {
            return bytes4(keccak256("performSellOrder((address,address,address,address,uint256,uint256,uint256,uint256,uint8,bytes32,bytes32),uint256)"));
        } else {
            return bytes4(0x0);
        }
    }
}

/// @title AirSwapHandler
/// @notice Handles the all AirSwap trades for the primary contract
contract AirSwapHandler is ExchangeHandler, AllowanceSetter {

    /*
    *   State Variables
    */

    AirSwap public exchange;
    WETH public weth;

    /*
    *   Types
    */

    struct OrderData {
        address makerAddress;
        address makerToken;
        address takerAddress;
        address takerToken;
        uint256 makerAmount;
        uint256 takerAmount;
        uint256 expiration;
        uint256 nonce;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    /// @notice Constructor
    /// @dev Calls the constructor of the inherited ExchangeHandler
    /// @param _exchange Address of the AirSwap exchange
    /// @param _weth Address of the weth contract we are using
    /// @param selectorProvider the provider for this exchanges function selectors
    /// @param totlePrimary the address of the totlePrimary contract
    /// @param errorReporter the address of the error reporter contract
    constructor(
        address _exchange,
        address _weth,
        address selectorProvider,
        address totlePrimary,
        address errorReporter
        /* ,address logger */
    )
        ExchangeHandler(selectorProvider, totlePrimary, errorReporter/*, logger*/)
        public
    {
        require(_exchange != address(0x0));
        require(_weth != address(0x0));
        exchange = AirSwap(_exchange);
        weth = WETH(_weth);
    }

    /*
    *   Public functions
    */

    /// @notice Gets the amount that Totle needs to give for this order
    /// @dev Uses the `onlySelf` modifier with public visibility as this function
    /// should only be called from functions which are inherited from the ExchangeHandler
    /// base contract.
    /// Uses `whenNotPaused` modifier to revert transactions when contract is "paused".
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
        return data.takerAmount;
    }

    /// @notice Perform exchange-specific checks on the given order
    /// @dev This function should be called to check for payload errors.
    /// Uses the `onlySelf` modifier with public visibility as this function
    /// should only be called from functions which are inherited from the ExchangeHandler
    /// base contract.
    /// Uses `whenNotPaused` modifier to revert transactions when contract is "paused".
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
        bytes32 orderHash;
        bytes32 prefixedHash;

        (orderHash, prefixedHash) = getOrderHash(data);

        return (
            data.takerAddress != data.makerAddress &&
            data.expiration >= block.timestamp &&
            ecrecover(prefixedHash, data.v, data.r, data.s) == data.makerAddress &&
            !exchange.fills(orderHash) &&
            data.takerAddress == address(this) &&
            Utils.tokenAllowanceAndBalanceSet(data.makerAddress, data.makerToken, data.makerAmount, address(exchange))
        );
    }

    /// @notice Perform a buy order at the exchange
    /// @dev Uses the `onlySelf` modifier with public visibility as this function
    /// should only be called from functions which are inherited from the ExchangeHandler
    /// base contract.
    /// Uses `whenNotPaused` modifier to revert transactions when contract is "paused".
    /// @param data OrderData struct containing order values
    /// @param amountToGiveForOrder amount that should be spent on this order
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
        /* logger.log("Performing AirSwap buy arg2: amountToGiveForOrder", amountToGiveForOrder); */
        if (data.takerAmount != amountToGiveForOrder || msg.value != data.takerAmount) {
            /* logger.log(
                "Taker amount is not equal to the amountToGiveForOrder or ether sent is not equal to the taker amount arg2: takerAmount, arg3: amountToGiveForOrder, arg4: msg.value",
                data.takerAmount,
                amountToGiveForOrder,
                msg.value
            ); */
            totlePrimary.transfer(msg.value);
            return (0,0);
        }

        fillAndValidate(data);

        /* logger.log("Filled and validated"); */

        if (!ERC20SafeTransfer.safeTransfer(data.makerToken, totlePrimary, data.makerAmount)) {
            errorReporter.revertTx("AirSwap: Unable to transfer bought tokens to primary");
        }

        return (data.takerAmount, data.makerAmount);
    }

    /// @notice Perform a sell order at the exchange
    /// @dev Uses the `onlySelf` modifier with public visibility as this function
    /// should only be called from functions which are inherited from the ExchangeHandler
    /// base contract
    /// Uses `whenNotPaused` modifier to revert transactions when contract is "paused".
    /// @param data OrderData struct containing order values
    /// @param amountToGiveForOrder amount that should be spent on this order
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
        /* logger.log("Performing AirSwap sell arg2: amountToGiveForOrder", amountToGiveForOrder); */
        /// @dev Primary will have transfered the tokens to us, revert if amount incorrect
        if (data.takerAmount != amountToGiveForOrder) {
            errorReporter.revertTx("AirSwap: takerAmount != amountToGiveForOrder");
        }

        if (data.makerToken != address(weth)) {
            /* logger.log("Maker token is not WETH", amountToGiveForOrder); */
            return (0,0);
        }

        approveAddress(address(exchange), data.takerToken);

        /* logger.log("Address approved arg6: exchange, arg7: takerToken", 0,0,0,0, exchange, data.takerToken); */

        fillAndValidate(data);

        /* logger.log("Filled and validated"); */

        weth.withdraw(data.makerAmount);

        /* logger.log("WETH withdrawal arg2: makerAmount", data.makerAmount); */

        totlePrimary.transfer(data.makerAmount);

        /* logger.log("Transfered WETH to Primary"); */

        return (data.takerAmount, data.makerAmount);
    }

    /*
    *   Internal functions
    */

    /// @notice Get both hash(data) and hash(prefix,hash(data))
    /// @param data OrderData struct containing order values
    /// @return orderHash the result of hashing the concatenated order data
    /// @return prefixedHash the result of orderHash prefixed by a message
    function getOrderHash(
        OrderData data
    )
        internal
        pure
        returns (bytes32 orderHash, bytes32 prefixedHash)
    {
        orderHash = keccak256(
            data.makerAddress,
            data.makerAmount,
            data.makerToken,
            data.takerAddress,
            data.takerAmount,
            data.takerToken,
            data.expiration,
            data.nonce
        );

        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        prefixedHash = keccak256(prefix, orderHash);
    }

    /// @notice Calls the fill function at airSwap, then validates the order was filled
    /// @dev If the order was not valid, this function will revert the transaction
    /// @param data OrderData struct containing order values
    function fillAndValidate(OrderData data) internal {

        exchange.fill.value(msg.value)(
            data.makerAddress,
            data.makerAmount,
            data.makerToken,
            data.takerAddress,
            data.takerAmount,
            data.takerToken,
            data.expiration,
            data.nonce,
            data.v,
            data.r,
            data.s
        );

        bytes32 orderHash;
        (orderHash, ) = getOrderHash(data);

        if (!exchange.fills(orderHash)) {
            errorReporter.revertTx("AirSwap: Order failed validation after execution");
        }
    }

    /*
    *   Payable fallback function
    */

    /// @notice payable fallback to allow handler or exchange contracts to return ether
    /// @dev only accounts containing code (ie. contracts) can send ether to this contract
    function() public payable whenNotPaused {
        // Check in here that the sender is a contract! (to stop accidents)
        uint256 size;
        address sender = msg.sender;
        assembly {
            size := extcodesize(sender)
        }
        if (size == 0) {
            errorReporter.revertTx("EOA cannot send ether to primary fallback");
        }
    }

}
