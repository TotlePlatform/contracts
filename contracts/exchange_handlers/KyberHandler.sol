pragma solidity 0.5.7;
pragma experimental ABIEncoderV2;

import "../lib/ERC20.sol";
import "../lib/SafeMath.sol";
import "../lib/Math.sol";
import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "./ExchangeHandler.sol";

interface ENSResolver {
    function getKyberNetworkAddress() external view returns (address);
}

interface Kyber {

    function trade(ERC20 src, uint srcAmount, ERC20 dest, address destAddress, uint maxDestAmount, uint minConversionRate, address walletId) external payable returns (uint);
    function maxGasPrice() external view returns(uint);
    function getExpectedRate(ERC20 source, ERC20 dest, uint srcQty) external view returns (uint expectedPrice, uint slippagePrice);
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
    }


    /// @notice Constructor
    /// @param _ensResolver Address of the ENS resolver
    constructor(
        address _ensResolver
        /* ,address logger */
    )
        public
    {
        ensResolver = ENSResolver(_ensResolver);
    }

    /*
    *   Internal functions
    */

    /// @notice Perform exchange-specific checks on the given order
    /// @dev This should be called to check for payload errors
    /// @param data OrderData struct containing order values
    /// @return checksPassed value representing pass or fail
    function staticExchangeChecks(
        OrderData memory data,
        Kyber exchange
    )
        public
        view
        whenNotPaused
        returns (bool checksPassed)
    {
        uint256 maxGasPrice = exchange.maxGasPrice();
        /* logger.log("Checking gas price arg2: tx.gasprice, arg3: maxGasPrice", tx.gasprice, maxGasPrice); */
        return (maxGasPrice >= tx.gasprice);
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
        uint256 originalBalance = getBalance(data.tokenFrom);
        Kyber exchange = resolveExchange();
        if(!staticExchangeChecks(data, exchange)){
            if(data.tokenFrom == Utils.eth_address()){
                msg.sender.transfer(msg.value);
            } else {
                ERC20SafeTransfer.safeTransfer(data.tokenFrom, msg.sender, availableToSpend);
            }
        }
        approve(address(exchange), data.tokenFrom);
        amountReceivedFromOrder = exchange.trade.value(
            data.tokenFrom == Utils.eth_address()? msg.value: 0)(
                ERC20(data.tokenFrom == Utils.eth_address() ? ETH_TOKEN_ADDRESS : data.tokenFrom),
                Math.min(availableToSpend, targetAmountIsSource ? targetAmount : availableToSpend),
                ERC20(data.tokenTo == Utils.eth_address() ? ETH_TOKEN_ADDRESS : data.tokenTo),
                msg.sender,
                targetAmountIsSource ? Utils.max_uint(): targetAmount,
                1,
                address(0x0)
        );
        uint256 newInputBalance = getBalance(data.tokenFrom);
        amountSpentOnOrder = originalBalance - newInputBalance;
        if(amountSpentOnOrder < availableToSpend){
            if(data.tokenFrom == Utils.eth_address()){
                msg.sender.transfer(SafeMath.sub(availableToSpend, amountSpentOnOrder));
            } else {
                ERC20SafeTransfer.safeTransfer(data.tokenFrom, msg.sender, SafeMath.sub(availableToSpend, amountSpentOnOrder));
            }
        }
    }

    function approve(
        address spender,
        address token
    )
        internal
    {
        if(token != Utils.eth_address()){
            approveAddress(spender, token);
        }
    }

    function getBalance(
        address token
    )
        internal
        returns (uint256 balance)
    {
        if(token == Utils.eth_address()){
            return address(this).balance;
        } else {
            return ERC20(token).balanceOf(address(this));
        }
    }

    function transfer(
        address token,
        uint256 amount
    )
        internal
    {
        if(token == Utils.eth_address()){
            msg.sender.transfer(amount);
        } else {
            ERC20SafeTransfer.safeTransfer(token, msg.sender, amount);
        }
    }

    function resolveExchange()
        internal
        view
        returns (Kyber)
    {
        return Kyber(ensResolver.getKyberNetworkAddress());
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
