pragma solidity 0.5.7;
pragma experimental ABIEncoderV2;

import "../lib/AllowanceSetter.sol";
import "../lib/Utils.sol";
import "../lib/Math.sol";
import "../lib/SafeMath.sol";
import "./ExchangeHandler.sol";

/// @title OasisInterface
/// @notice Exchange contract interface
interface OasisInterface {
    function sellAllAmount(
        address pay_gem,
        uint256 pay_amt,
        address buy_gem,
        uint256 min_fill_amount
    ) external returns (uint256 fill_amt);
}

interface WethInterface {
    function deposit() external payable;

    function withdraw(uint256 amount) external payable;
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
        address sourceAsset;
        address destinationAsset;
        uint256 maxOrderAmount;
    }

    /// @notice Constructor
    /// @dev Calls the constructor of the inherited ExchangeHandler
    /// @param oasisAddress the address of the Oasis exchange contract
    /// @param wethAddress the address of the weth contract
    constructor(address oasisAddress, address wethAddress)
        public
    /* , address logger */
    {
        oasis = OasisInterface(oasisAddress);
        weth = WethInterface(wethAddress);
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

        //Calculate amounts to spend
        uint256 amountToSpend = Math.min(
            Math.min(targetAmount, availableToSpend),
            data.maxOrderAmount
        );

        //Exit if we can't buy any
        if (amountToSpend == 0) {
            if (data.sourceAsset == Utils.eth_address()) {
                msg.sender.transfer(availableToSpend);
            } else {
                ERC20SafeTransfer.safeTransfer(
                    data.sourceAsset,
                    msg.sender,
                    availableToSpend
                );
            }
            return (0, 0);
        }

        if (data.sourceAsset == address(Utils.eth_address())) {
            weth.deposit.value(availableToSpend)();
        }

        approveAddress(
            address(oasis),
            data.sourceAsset == Utils.eth_address()
                ? address(weth)
                : data.sourceAsset
        );
        amountSpentOnOrder = amountToSpend;
        amountReceivedFromOrder = oasis.sellAllAmount(
            data.sourceAsset == Utils.eth_address()
                ? address(weth)
                : data.sourceAsset,
            amountToSpend,
            data.destinationAsset == Utils.eth_address()
                ? address(weth)
                : data.destinationAsset,
            1
        );

        //If we didn't spend all the tokens, send back to totlePrimary
        if (amountSpentOnOrder < availableToSpend) {
            if (data.sourceAsset == address(Utils.eth_address())) {
                weth.withdraw(availableToSpend - amountSpentOnOrder);
                msg.sender.transfer(availableToSpend - amountSpentOnOrder);
            } else {
                ERC20SafeTransfer.safeTransfer(
                    data.sourceAsset,
                    msg.sender,
                    availableToSpend - amountSpentOnOrder
                );
            }
        }

        //Send the purchased tokens back to totlePrimary
        if (data.destinationAsset == Utils.eth_address()) {
            weth.withdraw(amountReceivedFromOrder);
            msg.sender.transfer(amountReceivedFromOrder);
        } else {
            ERC20SafeTransfer.safeTransfer(
                data.destinationAsset,
                msg.sender,
                amountReceivedFromOrder
            );
        }
    }

    /// @notice Changes the current contract address set as WETH
    /// @param wethAddress the address of the new WETH contract
    function setWeth(address wethAddress) public onlyOwner {
        weth = WethInterface(wethAddress);
    }

    /// @notice Changes the current contract address set as WETH
    /// @param oasisAddress the address of the new WETH contract
    function setOasis(address oasisAddress) public onlyOwner {
        oasis = OasisInterface(oasisAddress);
    }

    /*
     *   Payable fallback function
     */

    /// @notice payable fallback to allow handler or exchange contracts to return ether
    /// @dev only accounts containing code (ie. contracts) can send ether to this contract
    function() external payable {}
}
