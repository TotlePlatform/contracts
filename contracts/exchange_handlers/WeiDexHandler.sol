pragma solidity 0.4.25;
pragma experimental ABIEncoderV2;

import "../lib/SafeMath.sol";
import "../lib/Math.sol";
import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "../lib/ErrorReporter.sol";
import "../lib/ERC20SafeTransfer.sol";
import "./ExchangeHandler.sol";
import "./SelectorProvider.sol";

interface WeiDex {
    function depositEthers() external payable;
    function withdrawEthers(uint256 amount) external;
    function depositTokens(address token, uint256 amount) external;
    function withdrawTokens(address token, uint256 amount) external;
    function takeBuyOrder(address[3] orderAddresses, uint256[3] orderValues, uint256 takerSellAmount, uint8 v, bytes32 r, bytes32 s) external;
    function takeSellOrder(address[3] orderAddresses, uint256[3] orderValues, uint256 takerSellAmount, uint8 v, bytes32 r, bytes32 s) external;
    function filledAmounts(bytes32 orderHash) external view returns (uint256);
    function feeRate() external view returns (uint256);
    function balances(address token, address user) external view returns (uint256);
}

/// @title WeiDexHandler
/// @notice Handles the all WeiDex trades for the primary contract
contract WeiDexHandler is ExchangeHandler, AllowanceSetter {

    /*
    *   State Variables
    */

    WeiDex public exchange;

    /*
    *   Types
    */

    struct OrderData {
        address[3] addresses; //Creator (maker), maker token address, taker token address. 0x0 for ETH
        uint256[3] values; // Amount of maker tokens, amount of taker tokens, nonce
        uint8 v; //Signature v
        bytes32 r; //Signature r
        bytes32 s; //Signature s
    }

    /// @notice Constructor
    /// @param _exchange Address of the WeiDex exchange
    /// @param totlePrimary the address of the totlePrimary contract
    /// @param errorReporter the address of the error reporter contract
    constructor(
        address _exchange,
        address totlePrimary,
        address errorReporter
        /* ,address logger */
    )
        ExchangeHandler(totlePrimary, errorReporter/*, logger*/)
        public
    {
        require(_exchange != address(0x0));
        exchange = WeiDex(_exchange);
    }

    /*
    *   Public functions
    */

    /// @notice Gets the amount that Totle needs to give for this order
    /// @dev Uses the `onlyTotle` modifier with public visibility as this function
    /// should only be called from functions which are inherited from the ExchangeHandler
    /// base contract
    /// @param order OrderData struct containing order values
    /// @return amountToGive amount taker needs to give in order to fill the order
    function getAmountToGive(
        OrderData order
    )
        public
        view
        onlyTotle
        returns (uint256 amountToGive)
    {
        amountToGive = getAvailableTakerVolume(order);
        /* logger.log("Remaining volume from weiDex", amountToGive); */
    }

    /// @notice Perform exchange-specific checks on the given order
    /// @dev Uses the `onlyTotle` modifier with public visibility as this function
    /// should only be called from functions which are inherited from the ExchangeHandler
    /// base contract.
    /// This should be called to check for payload errors.
    /// @param order OrderData struct containing order values
    /// @return checksPassed value representing pass or fail
    function staticExchangeChecks(
        OrderData order
    )
        public
        view
        onlyTotle
        returns (bool checksPassed)
    {
        bool correctMaker = order.addresses[0] == ecrecover(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", createHash(order))), order.v, order.r, order.s);
        bool hasAvailableVolume = exchange.filledAmounts(createHash(order)) < order.values[1];
        bool oneOfTokensIsEth = order.addresses[1] == address(0x0) || order.addresses[2] == address(0x0);
        return correctMaker && hasAvailableVolume && oneOfTokensIsEth;
    }

    /// @notice Perform a buy order at the exchange
    /// @dev Uses the `onlyTotle` modifier with public visibility as this function
    /// should only be called from functions which are inherited from the ExchangeHandler
    /// base contract
    /// @param order OrderData struct containing order values
    /// @param  amountToGiveForOrder amount that should be spent on this order
    /// @return amountSpentOnOrder the amount that would be spent on the order
    /// @return amountReceivedFromOrder the amount that was received from this order
    function performBuyOrder(
        OrderData order,
        uint256 amountToGiveForOrder
    )
        public
        payable
        onlyTotle
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        /* logger.log("Depositing eth to weiDex arg2: amountToGiveForOrder, arg3: ethBalance", amountToGiveForOrder, address(this).balance); */
        exchange.depositEthers.value(amountToGiveForOrder)();

        uint256 feeRate = exchange.feeRate();

        exchange.takeSellOrder(order.addresses, order.values, amountToGiveForOrder, order.v, order.r, order.s);

        amountSpentOnOrder = amountToGiveForOrder;
        amountReceivedFromOrder = SafeMath.div(SafeMath.mul(amountToGiveForOrder, order.values[0]), order.values[1]);
        amountReceivedFromOrder = SafeMath.sub(amountReceivedFromOrder, SafeMath.div(amountReceivedFromOrder, feeRate)); //Remove fee
        exchange.withdrawTokens(order.addresses[1], amountReceivedFromOrder);
        if (!ERC20SafeTransfer.safeTransfer(order.addresses[1], msg.sender, amountReceivedFromOrder)) {
            errorReporter.revertTx("Unable to transfer bought tokens to primary");
        }

        /* logger.log("Withdrawing tokens from weiDex arg2: amountReceivedFromOrder, arg3: amountSpentOnOrder", amountReceivedFromOrder, amountSpentOnOrder); */
    }

    /// @notice Perform a sell order at the exchange
    /// @dev Uses the `onlyTotle` modifier with public visibility as this function
    /// should only be called from functions which are inherited from the ExchangeHandler
    /// base contract
    /// @param order OrderData struct containing order values
    /// @param  amountToGiveForOrder amount that should be spent on this order
    /// @return amountSpentOnOrder the amount that would be spent on the order
    /// @return amountReceivedFromOrder the amount that was received from this order
    function performSellOrder(
        OrderData order,
        uint256 amountToGiveForOrder
    )
        public
        onlyTotle
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        approveAddress(address(exchange), order.addresses[2]);
        /* logger.log("Depositing tokens to weiDex arg2: amountToGiveForOrder", amountToGiveForOrder); */
        exchange.depositTokens(order.addresses[2], amountToGiveForOrder);

        uint256 feeRate = exchange.feeRate();
        uint256 amountToGive = SafeMath.div(SafeMath.mul(amountToGiveForOrder, feeRate), SafeMath.add(feeRate,1));

        exchange.takeBuyOrder(order.addresses, order.values, amountToGive, order.v, order.r, order.s);
        amountSpentOnOrder = amountToGiveForOrder;
        amountReceivedFromOrder = SafeMath.div(SafeMath.mul(amountToGive, order.values[0]), order.values[1]);

        /* logger.log("Withdrawing ether from weiDex arg2: amountReceivedFromOrder, arg3: amountSpentOnOrder", amountReceivedFromOrder, amountSpentOnOrder); */

        exchange.withdrawEthers(amountReceivedFromOrder);
        /* logger.log("Withdrawing ether arg2: amountReceived", amountReceivedFromOrder); */
        msg.sender.transfer(amountReceivedFromOrder);
    }

    /**
    * @dev Hashes the order.
    * @param order Order to be hashed.
    * @return hash result
    */
    function createHash(OrderData memory order)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(
                order.addresses[0],
                order.addresses[1],
                order.values[0],
                order.addresses[2],
                order.values[1],
                order.values[2],
                exchange
            )
        );
    }

    /**
    * @dev Gets available taker volume
    * @param order Order to get the available volume.
    * @return available volume
    */
    function getAvailableTakerVolume(OrderData memory order)
        internal
        view
        returns (uint256)
    {
        uint256 feeRate = exchange.feeRate();
        //Taker volume that's been filled
        uint256 filledTakerAmount = exchange.filledAmounts(createHash(order));
        //Amount of taker volume remaining based on filled amount
        uint256 remainingTakerVolumeFromFilled = SafeMath.sub(order.values[1], filledTakerAmount);
        //The maker's balance of eth
        uint256 remainingTakerVolumeFromMakerBalance;
        if(order.addresses[1]== address(0x0)){
            uint256 makerEthBalance = exchange.balances(address(0x0), order.addresses[0]);
            makerEthBalance = SafeMath.div(SafeMath.mul(makerEthBalance, feeRate), SafeMath.add(feeRate, 1));
            remainingTakerVolumeFromMakerBalance = SafeMath.div(SafeMath.mul(makerEthBalance, order.values[1]), order.values[0]);
        } else {
            uint256 makerTokenBalance = exchange.balances(order.addresses[1], order.addresses[0]);
            remainingTakerVolumeFromMakerBalance = SafeMath.div(SafeMath.mul(makerTokenBalance, order.values[1]), order.values[0]);
        }
        return Math.min(remainingTakerVolumeFromFilled, remainingTakerVolumeFromMakerBalance);
    }

    function getSelector(bytes4 genericSelector) public pure returns (bytes4) {
        if (genericSelector == getAmountToGiveSelector) {
            return bytes4(keccak256("getAmountToGive((address[3],uint256[3],uint8,bytes32,bytes32))"));
        } else if (genericSelector == staticExchangeChecksSelector) {
            return bytes4(keccak256("staticExchangeChecks((address[3],uint256[3],uint8,bytes32,bytes32))"));
        } else if (genericSelector == performBuyOrderSelector) {
            return bytes4(keccak256("performBuyOrder((address[3],uint256[3],uint8,bytes32,bytes32),uint256)"));
        } else if (genericSelector == performSellOrderSelector) {
            return bytes4(keccak256("performSellOrder((address[3],uint256[3],uint8,bytes32,bytes32),uint256)"));
        } else {
            return bytes4(0x0);
        }
    }

    /*
    *   Payable fallback function
    */

    /// @notice payable fallback to allow the exchange to return ether directly to this contract
    /// @dev note that only the exchange should be able to send ether to this contract
    function() public payable {
        if (msg.sender != address(exchange)) {
            errorReporter.revertTx("An address other than the exchange cannot send ether to EDHandler fallback");
        }
    }
}
