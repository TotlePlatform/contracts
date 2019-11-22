pragma solidity 0.5.7;
pragma experimental ABIEncoderV2;

import "../lib/AllowanceSetter.sol";
import "../lib/Utils.sol";
import "../lib/Math.sol";
import "../lib/SafeMath.sol";
import "./ExchangeHandler.sol";

/// @title Eth2DaiInterface
/// @notice Exchange contract interface
interface Eth2DaiInterface {
    function buy(uint id, uint quantity) external returns (bool);
    function getOffer(uint id) external view returns (uint makerAmount, ERC20 makerToken, uint takerAmount, ERC20 takerToken);
    function isActive(uint id) external view returns (bool);
}

interface WethInterface {
    function deposit() external payable;
    function withdraw(uint amount) external payable;
}

/// @title Eth2DaiHandler
/// @notice Handles the all Eth2Dai trades for the primary contract
contract Eth2DaiHandler is ExchangeHandler, AllowanceSetter {

    /*
    *   State Variables
    */

    Eth2DaiInterface public eth2dai;
    WethInterface public weth;

    /*
    *   Types
    */

    struct OrderData {
        uint256 offerId;
    }


    /// @notice Constructor
    /// @dev Calls the constructor of the inherited ExchangeHandler
    /// @param eth2daiAddress the address of the Eth2Dai exchange contract
    /// @param wethAddress the address of the weth contract
    constructor(
        address eth2daiAddress,
        address wethAddress
        /* , address logger */
    )
        public
    {
        eth2dai = Eth2DaiInterface(eth2daiAddress);
        weth = WethInterface(wethAddress);
    }

    struct OfferInfo {
        uint256 makerAmount;
        address makerToken;
        uint256 takerAmount;
        address takerToken;
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
        //Decode order data
        OrderData memory data = abi.decode(genericPayload, (OrderData));
    
        OfferInfo memory offer;

        //Fetch offer data
        {
            ERC20 makerTokenERC20;
            ERC20 takerTokenERC20;
            uint256 makerAmount;
            uint256 takerAmount;
            (makerAmount,makerTokenERC20,takerAmount,takerTokenERC20) = eth2dai.getOffer(data.offerId);
            offer = OfferInfo(makerAmount, address(makerTokenERC20), takerAmount, address(takerTokenERC20));
        }

        //Validate order is active, exit if not
        if(!eth2dai.isActive(data.offerId)){
            if(offer.takerToken == address(weth)){
                msg.sender.transfer(availableToSpend);
            } else {
                ERC20SafeTransfer.safeTransfer(offer.takerToken, msg.sender, availableToSpend);
            }
            return (0,0);
        }

        //Calculate amounts to buy/spend
        uint256 amountToBuy = targetAmountIsSource ? Math.min(Math.min(availableToSpend, offer.takerAmount), targetAmount) * offer.makerAmount / offer.takerAmount : Math.min(targetAmount, offer.makerAmount);

        //Exit if we can't buy any
        if(amountToBuy == 0){
            if(offer.takerToken == address(weth)){
                msg.sender.transfer(availableToSpend);
            } else {
                ERC20SafeTransfer.safeTransfer(offer.takerToken, msg.sender, availableToSpend);
            }
            return (0,0);
        }

        if(offer.takerToken == address(weth)){
            weth.deposit.value(availableToSpend)();
        }
        
        approveAddress(address(eth2dai), offer.takerToken);

        if (!eth2dai.buy(data.offerId, amountToBuy)){
          revert("Eth2Dai buy failed");
        }

        //Calculate actual amounts spent and got
        uint256 newMakerAmount;
        uint256 newTakerAmount;
        (newMakerAmount,,newTakerAmount,) = eth2dai.getOffer(data.offerId);

        amountReceivedFromOrder = offer.makerAmount - newMakerAmount;
        amountSpentOnOrder = offer.takerAmount - newTakerAmount;

        //If we didn't spend all the tokens, send back to totlePrimary
        if (amountSpentOnOrder < availableToSpend){
            if(offer.takerToken == address(weth)){
                weth.withdraw(availableToSpend - amountSpentOnOrder);
                msg.sender.transfer(availableToSpend - amountSpentOnOrder);
            } else {
                ERC20SafeTransfer.safeTransfer(offer.takerToken, msg.sender, availableToSpend - amountSpentOnOrder);
            }
        }

        //Send the purchased tokens back to totlePrimary
        if(offer.makerToken == address(weth)){
            weth.withdraw(amountReceivedFromOrder);
            msg.sender.transfer(amountReceivedFromOrder);
        } else {
            ERC20SafeTransfer.safeTransfer(offer.makerToken, msg.sender, amountReceivedFromOrder);
        }
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
            revert("EOA cannot send ether to primary fallback");
        }
    }
}
