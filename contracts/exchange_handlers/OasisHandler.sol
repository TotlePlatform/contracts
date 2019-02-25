pragma solidity 0.4.25;
pragma experimental ABIEncoderV2;

import "../lib/AllowanceSetter.sol";
import "../lib/ErrorReporter.sol";
import "../lib/Math.sol";
import "../lib/SafeMath.sol";
import "./ExchangeHandler.sol";
import "./SelectorProvider.sol";

/// @title OasisInterface
/// @notice Exchange contract interface
interface OasisInterface {
    function buy(uint id, uint quantity) external returns (bool);
    function getOffer(uint id) external constant returns (uint, ERC20, uint, ERC20);
    function isActive(uint id) external constant returns (bool);
}

interface WethInterface {
    function deposit() external payable;
    function withdraw(uint amount) external payable;
}

/// @title OasisHandler
/// @notice Handles the all Oasis trades for the primary contract
contract OasisHandler is ExchangeHandler, AllowanceSetter {

    /*
    *   State Variables
    */

    OasisInterface public oasis;
    WethInterface public weth;

    /*
    *   Types
    */

    struct OrderData {
        uint256 offerId;
        uint256 maxAmountToSpend;
    }


    /// @notice Constructor
    /// @dev Calls the constructor of the inherited ExchangeHandler
    /// @param oasisAddress the address of the oasis exchange contract
    /// @param wethAddress the address of the weth contract
    /// @param totlePrimary the address of the totlePrimary contract
    constructor(
        address oasisAddress,
        address wethAddress,
        address totlePrimary,
        address errorReporter
        /* , address logger */
    )
        ExchangeHandler(totlePrimary, errorReporter/*,logger*/)
        public
    {
        require(oasisAddress != address(0x0));
        require(wethAddress != address(0x0));
        oasis = OasisInterface(oasisAddress);
        weth = WethInterface(wethAddress);
    }


    /*
    *   Public functions
    */

    /// @notice Gets the amount that Totle needs to give for this order
    /// @dev Uses the `onlyTotle` modifier with public visibility as this function
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
        onlyTotle
        returns (uint256 amountToGive)
    {
        uint256 availableGetAmount;
        (availableGetAmount,,,) = oasis.getOffer(data.offerId);
        /* logger.log("Oasis order available amount arg2: availableGetAmount", availableGetAmount); */
        return availableGetAmount > data.maxAmountToSpend ? data.maxAmountToSpend : availableGetAmount;
    }


    /// @notice Perform exchange-specific checks on the given order
    /// @dev This function should be called to check for payload errors.
    /// Uses the `onlyTotle` modifier with public visibility as this function
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
        onlyTotle
        returns (bool checksPassed)
    {

        /* logger.log("Oasis static exchange checks"); */
        // Check if the offer is active
        if (!oasis.isActive(data.offerId)){
            /* logger.log("Oasis offer is not active arg2: offerId", data.offerId); */
            return false;
        }

        // Check if the pay_gem or buy_gem is weth
        address pay_gem;
        address buy_gem;
        (,pay_gem,,buy_gem) = oasis.getOffer(data.offerId);

        bool isBuyOrPayWeth = pay_gem == address(weth) || buy_gem == address(weth);
        if (!isBuyOrPayWeth){
            /* logger.log("Oasis offer's base pair is not WETH arg6: pay_gem, arg7: buy_gem", 0,0,0,0, pay_gem, buy_gem); */
            return false;
        }

        return true;
    }

    /// @notice Perform a buy order at the exchange
    /// @dev Uses the `onlyTotle` modifier with public visibility as this function
    /// should only be called from functions which are inherited from the ExchangeHandler
    /// base contract.
    /// Uses `whenNotPaused` modifier to revert transactions when contract is "paused".
    /// @param data OrderData struct containing order values
    /// @param amountToSpend amount that should be spent on this order
    /// @return amountSpentOnOrder the amount that would be spent on the order
    /// @return amountReceivedFromOrder the amount that was received from this order
    function performBuyOrder(
        OrderData data,
        uint256 amountToSpend
    )
        public
        payable
        whenNotPaused
        onlyTotle
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        /* logger.log("Performing Oasis buy order arg2: amountSpentOnOrder, arg3: amountReceivedFromOrder", amountSpentOnOrder, amountReceivedFromOrder); */
        if (msg.value != amountToSpend){

            /* logger.log("Ether sent is not equal to amount to spend arg2: amountToSpend, arg3: msg.value", amountToSpend, msg.value); */
            msg.sender.transfer(msg.value);
            return (0,0);
        }

        //Convert ETH to Weth
        weth.deposit.value(amountToSpend)();

        /* logger.log("Converted to WETH"); */

        //Approve oasis to move weth
        approveAddress(address(oasis), address(weth));

        /* logger.log("Address approved"); */

        //Fetch offer data and validate buy gem is weth
        uint256 maxPayGem;
        address payGem;
        uint256 maxBuyGem;
        address buyGem;
        (maxPayGem,payGem,maxBuyGem,buyGem) = oasis.getOffer(data.offerId);

        if (buyGem != address(weth)){
            errorReporter.revertTx("buyGem != address(weth)");
        }

        //Calculate quantity to buy
        uint256 amountToBuy = SafeMath.div( SafeMath.mul(amountToSpend, maxPayGem), maxBuyGem);

        if (!oasis.buy(data.offerId, amountToBuy)){
            errorReporter.revertTx("Oasis buy failed");
        }

        //Calculate actual amounts spent and got
        uint256 newMaxPayGem;
        uint256 newMaxBuyGem;
        (newMaxPayGem,,newMaxBuyGem,) = oasis.getOffer(data.offerId);

        amountReceivedFromOrder = maxPayGem - newMaxPayGem;
        amountSpentOnOrder = maxBuyGem - newMaxBuyGem;

        //If we didn't spend all the eth, withdraw it from weth and send back to totlePrimary
        if (amountSpentOnOrder < amountToSpend){
          /* logger.log("Got some ether left, withdrawing arg2: amountSpentOnOrder, arg3: amountToSpend", amountSpentOnOrder, amountToSpend); */
          weth.withdraw(amountToSpend - amountSpentOnOrder);
          msg.sender.transfer(amountToSpend - amountSpentOnOrder);
        }

        //Send the purchased tokens back to totlePrimary
        if (!ERC20(payGem).transfer(msg.sender, amountReceivedFromOrder)){
            errorReporter.revertTx("Unable to transfer bought tokens to totlePrimary");
        }
    }

    /// @notice Perform a sell order at the exchange
    /// @dev Uses the `onlyTotle` modifier with public visibility as this function
    /// should only be called from functions which are inherited from the ExchangeHandler
    /// base contract
    /// Uses `whenNotPaused` modifier to revert transactions when contract is "paused".
    /// @param data OrderData struct containing order values
    /// @param amountToSpend amount that should be spent on this order
    /// @return amountSpentOnOrder the amount that would be spent on the order
    /// @return amountReceivedFromOrder the amount that was received from this order
    function performSellOrder(
        OrderData data,
        uint256 amountToSpend
    )
        public
        whenNotPaused
        onlyTotle
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
      //Fetch offer data and validate buy gem is weth
      uint256 maxPayGem;
      address payGem;
      uint256 maxBuyGem;
      address buyGem;
      (maxPayGem,payGem,maxBuyGem,buyGem) = oasis.getOffer(data.offerId);

      /* logger.log("Performing Oasis sell order arg2: amountToSpend", amountToSpend); */

      if (payGem != address(weth)){
          errorReporter.revertTx("payGem != address(weth)");
      }

      //Approve oasis to move buy gem
      approveAddress(address(oasis), address(buyGem));

      /* logger.log("Address approved"); */

      //Calculate quantity to buy
      uint256 amountToBuy = SafeMath.div( SafeMath.mul(amountToSpend, maxPayGem), maxBuyGem);
      if(amountToBuy == 0){
          /* logger.log("Amount to buy is zero, amountToSpend was likely too small to get any. Did the previous order fill all but a small amount? arg2: amountToSpend", amountToSpend); */
          ERC20(buyGem).transfer(msg.sender, amountToSpend);
          return (0, 0);
      }
      if (!oasis.buy(data.offerId, amountToBuy)){
          errorReporter.revertTx("Oasis buy failed");
      }

      //Calculate actual amounts spent and got
      uint256 newMaxPayGem;
      uint256 newMaxBuyGem;
      (newMaxPayGem,,newMaxBuyGem,) = oasis.getOffer(data.offerId);

      amountReceivedFromOrder = maxPayGem - newMaxPayGem;
      amountSpentOnOrder = maxBuyGem - newMaxBuyGem;

      //If we didn't spend all the tokens, withdraw it from weth and send back to totlePrimary
      if (amountSpentOnOrder < amountToSpend){
        /* logger.log("Got some tokens left, withdrawing arg2: amountSpentOnOrder, arg3: amountToSpend", amountSpentOnOrder, amountToSpend); */
        ERC20(buyGem).transfer(msg.sender, amountToSpend - amountSpentOnOrder);
      }

      //Send the purchased tokens back to totlePrimary
      weth.withdraw(amountReceivedFromOrder);
      msg.sender.transfer(amountReceivedFromOrder);
    }

    /// @notice Changes the current contract address set as WETH
    /// @param wethAddress the address of the new WETH contract
    function setWeth(
        address wethAddress
    )
        public
        onlyOwner
    {
        require(wethAddress != address(0x0));
        weth = WethInterface(wethAddress);
    }

    function getSelector(bytes4 genericSelector) public pure returns (bytes4) {
        if (genericSelector == getAmountToGiveSelector) {
            return bytes4(keccak256("getAmountToGive((uint256,uint256))"));
        } else if (genericSelector == staticExchangeChecksSelector) {
            return bytes4(keccak256("staticExchangeChecks((uint256,uint256))"));
        } else if (genericSelector == performBuyOrderSelector) {
            return bytes4(keccak256("performBuyOrder((uint256,uint256),uint256)"));
        } else if (genericSelector == performSellOrderSelector) {
            return bytes4(keccak256("performSellOrder((uint256,uint256),uint256)"));
        } else {
            return bytes4(0x0);
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
