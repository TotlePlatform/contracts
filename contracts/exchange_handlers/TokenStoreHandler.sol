pragma solidity 0.4.25;
pragma experimental ABIEncoderV2;

import "../lib/ERC20.sol";
import "../lib/SafeMath.sol";
import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "../lib/ErrorReporter.sol";
import "./ExchangeHandler.sol";

interface TokenStoreExchange {

   //Trading
   function trade(address _tokenGet, uint _amountGet, address _tokenGive, uint _amountGive,
       uint _expires, uint _nonce, address _user, uint8 _v, bytes32 _r, bytes32 _s, uint _amount) external;

   // Get info
   function fee() external constant returns(uint256);
   function availableVolume(address _tokenGet, uint _amountGet, address _tokenGive, uint _amountGive, uint _expires,
       uint _nonce, address _user, uint8 _v, bytes32 _r, bytes32 _s) external constant returns(uint);

   //Balance deposit/withdraw functions
   function deposit() external payable; //Deposit ETH
   function withdraw(uint256 amount) external; //Withdraw ETH
   function depositToken(address _token, uint _amount) external;
   function withdrawToken(address _token, uint _amount) external;

}

/// @title TokenStoreSelectorProvider
/// @notice Provides this exchange implementation with correctly formatted function selectors
contract TokenStoreSelectorProvider is SelectorProvider {
    function getSelector(bytes4 genericSelector) public pure returns (bytes4) {
        if (genericSelector == getAmountToGive) {
            return bytes4(keccak256("getAmountToGive((address,uint256,address,uint256,uint256,uint256,address,uint8,bytes32,bytes32))"));
        } else if (genericSelector == staticExchangeChecks) {
            return bytes4(keccak256("staticExchangeChecks((address,uint256,address,uint256,uint256,uint256,address,uint8,bytes32,bytes32))"));
        } else if (genericSelector == performBuyOrder) {
            return bytes4(keccak256("performBuyOrder((address,uint256,address,uint256,uint256,uint256,address,uint8,bytes32,bytes32),uint256)"));
        } else if (genericSelector == performSellOrder) {
            return bytes4(keccak256("performSellOrder((address,uint256,address,uint256,uint256,uint256,address,uint8,bytes32,bytes32),uint256)"));
        } else {
            return bytes4(0x0);
        }
    }
}

/// @title Handler for TokenStore exchange
contract TokenStoreHandler is ExchangeHandler, AllowanceSetter {

    /*
    *   Types
    */
    struct OrderData {
        address takerToken; //For a Totle sell, takerToken is the token address
        uint256 takerAmount;
        address makerToken; //For a Totle sell, makerToken is 0x0 (ETH)
        uint256 makerAmount;
        uint256 expires;
        uint256 nonce;
        address user; //Maker
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    TokenStoreExchange exchange;


    /// @notice Constructor
    /// @param _exchange the address of the token store exchange
    /// @param _selectorProvider the provider for this exchanges function selectors
    /// @param _totlePrimary the address of the totlePrimary contract
    /// @param errorReporter the address of of the errorReporter contract
    constructor(
        address _exchange,
        address _selectorProvider,
        address _totlePrimary,
        address errorReporter/*,
        address logger*/
    ) ExchangeHandler(_selectorProvider, _totlePrimary, errorReporter/*, logger*/) public {
        exchange = TokenStoreExchange(_exchange);
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
        uint256 feePercentage = exchange.fee();
        uint256 availableVolume = exchange.availableVolume(data.takerToken, data.takerAmount, data.makerToken, data.makerAmount, data.expires,
            data.nonce, data.user, data.v, data.r, data.s);
        uint256 fee = SafeMath.div(SafeMath.mul(availableVolume, feePercentage), 1 ether);
        return SafeMath.add(availableVolume, fee);
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
        bytes32 hash = sha256(abi.encodePacked(address(exchange), data.takerToken, data.takerAmount, data.makerToken, data.makerAmount, data.expires, data.nonce));
        if (ecrecover(sha3(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)), data.v, data.r, data.s) != data.user || block.number > data.expires) {
            return false;
        }
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
        amountSpentOnOrder = amountToGiveForOrder;
        exchange.deposit.value(amountToGiveForOrder)();
        uint256 amountToSpend = removeFee(amountToGiveForOrder);
        amountReceivedFromOrder = SafeMath.div(SafeMath.mul(amountToSpend, data.makerAmount), data.takerAmount);
        exchange.trade(data.takerToken, data.takerAmount, data.makerToken, data.makerAmount, data.expires, data.nonce, data.user, data.v, data.r, data.s, amountToSpend);
        /* logger.log("Performing TokenStore buy order arg2: amountSpentOnOrder, arg3: amountReceivedFromOrder", amountSpentOnOrder, amountReceivedFromOrder);  */
        exchange.withdrawToken(data.makerToken, amountReceivedFromOrder);
        if (!ERC20SafeTransfer.safeTransfer(data.makerToken, totlePrimary, amountReceivedFromOrder)){
            errorReporter.revertTx("Failed to transfer tokens to totle primary");
        }

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
        amountSpentOnOrder = amountToGiveForOrder;
        approveAddress(address(exchange), data.takerToken);
        exchange.depositToken(data.takerToken, amountToGiveForOrder);
        uint256 amountToSpend = removeFee(amountToGiveForOrder);
        amountReceivedFromOrder = SafeMath.div(SafeMath.mul(amountToSpend, data.makerAmount), data.takerAmount);
        exchange.trade(data.takerToken, data.takerAmount, data.makerToken, data.makerAmount, data.expires, data.nonce, data.user, data.v, data.r, data.s, amountToSpend);
        /* logger.log("Performing TokenStore sell order arg2: amountSpentOnOrder, arg3: amountReceivedFromOrder",amountSpentOnOrder,amountReceivedFromOrder); */
        exchange.withdraw(amountReceivedFromOrder);
        totlePrimary.transfer(amountReceivedFromOrder);
    }

    function removeFee(uint256 totalAmount) internal constant returns (uint256){
      uint256 feePercentage = exchange.fee();
      return SafeMath.div(SafeMath.mul(totalAmount, 1 ether), SafeMath.add(feePercentage, 1 ether));

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
