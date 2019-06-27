pragma solidity 0.5.7;
pragma experimental ABIEncoderV2;

import "../lib/ERC20.sol";
import "../lib/SafeMath.sol";
import "../lib/Math.sol";
import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "./ExchangeHandler.sol";

interface UniswapExchange {

    //Trading
    //Eth to token
    function ethToTokenTransferInput(uint256 min_tokens, uint256 deadline, address recipient) external payable returns (uint256  tokens_bought);
    function ethToTokenTransferOutput(uint256 tokens_bought, uint256 deadline, address recipient) external payable returns (uint256  eth_sold);
    
    //Token to eth
    function tokenToEthTransferInput(uint256 tokens_sold, uint256 min_tokens, uint256 deadline, address recipient) external returns (uint256  eth_bought);
    function tokenToEthTransferOutput(uint256 eth_bought, uint256 max_tokens, uint256 deadline, address recipient) external returns (uint256  tokens_sold);

    //Token to token
    function tokenToTokenTransferInput(uint256 tokens_sold, uint256 min_tokens_bought, uint256 min_eth_bought, uint256 deadline, address recipient, address token_addr) external returns (uint256  tokens_bought);
    function tokenToTokenTransferOutput(uint256 tokens_bought, uint256 max_tokens_sold, uint256 max_eth_sold, uint256 deadline, address recipient, address token_addr) external returns (uint256  tokens_sold);

    // Get Price
    function getEthToTokenInputPrice(uint256 eth_sold) external view returns (uint256);
    function getTokenToEthInputPrice(uint256 tokens_sold) external view returns (uint256);

    function tokenAddress() external view returns (address);
}

interface UniswapFactory {
    function getExchange(address token) external view returns (address exchange);
}

/// @title Handler for Uniswap exchange
contract UniswapHandler is ExchangeHandler, AllowanceSetter {
    /*
    *   Types
    */

    struct OrderData {
        address sourceToken;
        address destinationToken;
    }

    UniswapFactory private uniswapFactory;

    /// @notice Constructor
    constructor(
        address _uniswapFactory
    ) 
        public
    {
        uniswapFactory = UniswapFactory(_uniswapFactory);
    }

    /*
    *   Internal functions
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
        UniswapExchange ex = UniswapExchange(uniswapFactory.getExchange(data.sourceToken == Utils.eth_address() ? data.destinationToken: data.sourceToken));
        approve(data.sourceToken, address(ex));
        uint256 maxToSpend = getMaxToSpend(targetAmountIsSource, targetAmount, availableToSpend);
        if(data.sourceToken == Utils.eth_address()){
            return performEthToToken(data, ex, targetAmountIsSource, targetAmount, maxToSpend, availableToSpend);
        } else if(data.destinationToken == Utils.eth_address()){
            return performTokenToEth(data, ex, targetAmountIsSource, targetAmount, maxToSpend, availableToSpend);
        } else {
            return performTokenToToken(data, ex, targetAmountIsSource, targetAmount, maxToSpend, availableToSpend);
        }
    }

    function performEthToToken(
        OrderData memory data,
        UniswapExchange ex, 
        bool targetAmountIsSource, 
        uint256 targetAmount,
        uint256 maxToSpend,
        uint256 availableToSpend
    ) 
        internal 
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder) 
    {
        if(targetAmountIsSource){
            amountReceivedFromOrder = ex.ethToTokenTransferInput.value(maxToSpend)(1, block.timestamp, msg.sender);
            amountSpentOnOrder = maxToSpend;
            if(maxToSpend < availableToSpend) {
                msg.sender.transfer(availableToSpend - amountSpentOnOrder);
            }
        } else {
            amountSpentOnOrder = ex.ethToTokenTransferOutput.value(maxToSpend)(targetAmount, block.timestamp, msg.sender);
            amountReceivedFromOrder = targetAmount;
            if(availableToSpend - amountSpentOnOrder > 0){
                msg.sender.transfer(availableToSpend - amountSpentOnOrder);
            }
        }
    }

    function performTokenToEth(
        OrderData memory data,
        UniswapExchange ex,
        bool targetAmountIsSource,
        uint256 targetAmount,
        uint256 maxToSpend,
        uint256 availableToSpend
    )
        internal
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        if(targetAmountIsSource){
            amountReceivedFromOrder = ex.tokenToEthTransferInput(maxToSpend, 1, block.timestamp, msg.sender);
            amountSpentOnOrder = maxToSpend;
            if(maxToSpend < availableToSpend) {
                ERC20SafeTransfer.safeTransfer(data.sourceToken, msg.sender, availableToSpend - amountSpentOnOrder);
            }
        } else {
            amountSpentOnOrder = ex.tokenToEthTransferOutput(targetAmount, maxToSpend, block.timestamp, msg.sender);
            amountReceivedFromOrder = targetAmount;
            if(amountSpentOnOrder < availableToSpend){
                ERC20SafeTransfer.safeTransfer(data.sourceToken, msg.sender, availableToSpend - amountSpentOnOrder);
            }
        }
    }

    function performTokenToToken(
        OrderData memory data,
        UniswapExchange ex,
        bool targetAmountIsSource,
        uint256 targetAmount,
        uint256 maxToSpend, 
        uint256 availableToSpend
    )
        internal
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        
        if(targetAmountIsSource){
            amountReceivedFromOrder = ex.tokenToTokenTransferInput(maxToSpend, 1, 1, block.timestamp, msg.sender, data.destinationToken);
            amountSpentOnOrder = maxToSpend;
            if(availableToSpend > amountSpentOnOrder){
                ERC20SafeTransfer.safeTransfer(data.sourceToken, msg.sender, availableToSpend - amountSpentOnOrder);
            }
        } else {
            amountSpentOnOrder = ex.tokenToTokenTransferOutput(targetAmount, maxToSpend,  Utils.max_uint(), block.timestamp, msg.sender, data.destinationToken);
            amountReceivedFromOrder = targetAmount;
            if(amountSpentOnOrder < availableToSpend){
                ERC20SafeTransfer.safeTransfer(data.sourceToken, msg.sender, availableToSpend - amountSpentOnOrder);
            }
        }
    }

    function getMaxToSpend(
        bool targetAmountIsSource,
        uint256 targetAmount,
        uint256 availableToSpend
    )
        internal
        returns (uint256 max)
    {
        max = availableToSpend;
        if(targetAmountIsSource){
            max = Math.min(max, targetAmount);
        }
        return max;
    }

    function approve(
        address token,
        address taker
    )
        internal 
    {
        if(token != Utils.eth_address()){
            approveAddress(taker, token);
        }
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
