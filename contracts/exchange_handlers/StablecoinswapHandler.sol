pragma solidity 0.5.7;
pragma experimental ABIEncoderV2;

import "../lib/ERC20.sol";
import "../lib/SafeMath.sol";
import "../lib/Math.sol";
import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "./ExchangeHandler.sol";

interface Stablecoinswap {

    //Trading
    function swapTokens(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 minimumOutputAmount,
        uint256 deadline
    )
        external
        payable
        returns (uint256 outputAmount);

    //Pricing
    function tokenOutputAmountAfterFees(
        uint256 inputAmount,
        address inputToken,
        address outputToken
    )
        external
        returns (uint256 outputAmount);
    
    function tokenExchangeRateAfterFees(
        address inputToken,
        address outputToken
    )
        external
        returns (uint256 exchangeRate);

    function tokenPrice(
        address token
    )
        external
        returns (uint256 exchangeRate);
}


/// @title Handler for Stablecoinswap exchange
contract StablecoinswapHandler is ExchangeHandler, AllowanceSetter {
    /*
    *   Types
    */

    struct OrderData {
        address sourceToken;
        address destinationToken;
    }
    
    uint256 private constant EXCHANGE_RATE_MULTIPLIER = 10000000000000000000000;
    Stablecoinswap public stablecoinswap;

    /// @notice Constructor
    constructor(
        address _stablecoinswap
    )
        public
    {
        stablecoinswap = Stablecoinswap(_stablecoinswap);
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
        if(data.sourceToken == 0x8dd5fbCe2F6a956C3022bA3663759011Dd51e73E){
            data.sourceToken = 0x0000000000085d4780B73119b644AE5ecd22b376;
        } else if(data.destinationToken == 0x8dd5fbCe2F6a956C3022bA3663759011Dd51e73E){
            data.destinationToken = 0x0000000000085d4780B73119b644AE5ecd22b376;
        }
        approve(data.sourceToken, address(stablecoinswap));
        uint256 maxToSpend = getMaxToSpend(targetAmountIsSource, targetAmount, availableToSpend);
        uint256 maxOutput = ERC20(data.destinationToken).balanceOf(address(stablecoinswap));
        uint256 amountToSpend = Math.min(
            maxToSpend,
            maxOutput * EXCHANGE_RATE_MULTIPLIER / stablecoinswap.tokenExchangeRateAfterFees(data.sourceToken, data.destinationToken)
        );
        amountReceivedFromOrder = stablecoinswap.swapTokens(data.sourceToken, data.destinationToken, amountToSpend, 1, block.timestamp+1);
        amountSpentOnOrder = amountToSpend;
        if(availableToSpend > amountSpentOnOrder){
            ERC20SafeTransfer.safeTransfer(data.sourceToken, msg.sender, availableToSpend - amountSpentOnOrder);
        }
        ERC20SafeTransfer.safeTransfer(data.destinationToken, msg.sender, amountReceivedFromOrder);
    }

    function updateStablecoinswapContract(
        address newStablecoinswap
    )
        public
        onlyOwner
    {
        stablecoinswap = Stablecoinswap(newStablecoinswap);
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
