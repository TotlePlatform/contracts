pragma solidity 0.5.7;
pragma experimental ABIEncoderV2;

import "../lib/AllowanceSetter.sol";
import "../lib/ERC20SafeTransfer.sol";
/* import "../lib/Logger.sol"; */
import "../lib/Math.sol";
import "../lib/SafeMath.sol";
import "../lib/Utils.sol";
import "../lib/WETH.sol";
import "./ExchangeHandler.sol";

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
    constructor(
        address _exchange,
        address _weth
        /* ,address logger */
    )
        public
    {
        exchange = AirSwap(_exchange);
        weth = WETH(_weth);
    }

    /*
    *   Public functions
    */

    /// @notice Perform exchange-specific checks on the given order
    /// @param data OrderData struct containing order values
    /// @return checksPassed value representing pass or fail
    function staticExchangeChecks(
        OrderData memory data
    )
        internal
        view
        returns (bool checksPassed)
    {
        bytes32 orderHash;
        bytes32 prefixedHash;

        (orderHash, prefixedHash) = getOrderHash(data);

        return (
            data.expiration >= block.timestamp &&
            !exchange.fills(orderHash) &&
            Utils.tokenAllowanceAndBalanceSet(data.makerAddress, data.makerToken, data.makerAmount, address(exchange))
        );
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
            if(data.takerToken == Utils.eth_address()){
                msg.sender.transfer(availableToSpend);
            } else {
                ERC20SafeTransfer.safeTransfer(data.takerToken, msg.sender, availableToSpend);
            }
        }
        if(data.takerToken != Utils.eth_address()){
            approveAddress(address(exchange), data.takerToken);
        }
        amountSpentOnOrder = data.takerAmount;
        amountReceivedFromOrder = data.makerAmount;
        fillAndValidate(data, data.takerToken == Utils.eth_address() ? amountSpentOnOrder : 0);

        if(availableToSpend > amountSpentOnOrder){
            if(data.takerToken == Utils.eth_address()){
                msg.sender.transfer(availableToSpend - amountSpentOnOrder);
            } else {
                ERC20SafeTransfer.safeTransfer(data.takerToken, msg.sender, availableToSpend - amountSpentOnOrder);
            }
        }
        if(data.makerToken == address(weth)){
            weth.withdraw(amountReceivedFromOrder);
            msg.sender.transfer(amountReceivedFromOrder);
        } else {
            ERC20SafeTransfer.safeTransfer(data.makerToken, msg.sender, amountReceivedFromOrder);
        }
    }

    /*
    *   Internal functions
    */

    /// @notice Get both hash(data) and hash(prefix,hash(data))
    /// @param data OrderData struct containing order values
    /// @return orderHash the result of hashing the concatenated order data
    /// @return prefixedHash the result of orderHash prefixed by a message
    function getOrderHash(
        OrderData memory data
    )
        internal
        pure
        returns (bytes32 orderHash, bytes32 prefixedHash)
    {
        orderHash = keccak256(abi.encodePacked(
            data.makerAddress,
            data.makerAmount,
            data.makerToken,
            data.takerAddress,
            data.takerAmount,
            data.takerToken,
            data.expiration,
            data.nonce
        ));

        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        prefixedHash = keccak256(abi.encodePacked(prefix, orderHash));
    }

    /// @notice Calls the fill function at airSwap, then validates the order was filled
    /// @dev If the order was not valid, this function will revert the transaction
    /// @param data OrderData struct containing order values
    function fillAndValidate(OrderData memory data, uint256 valueToSend) internal {

        exchange.fill.value(data.takerToken == Utils.eth_address() ? data.takerAmount : 0)(
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

        require(exchange.fills(orderHash), "AirSwap: Order failed validation after execution");
    }

    /*
    *   Payable fallback function
    */

    /// @notice payable fallback to allow handler or exchange contracts to return ether
    /// @dev only accounts containing code (ie. contracts) can send ether to this contract
    function() external payable whenNotPaused {
        // Check in here that the sender is a contract! (to stop accidents)
        uint256 size;
        address sender = msg.sender;
        assembly {
            size := extcodesize(sender)
        }
        if (size == 0) {
            revert("EOA cannot send ether to airswap fallback");
        }
    }

}
