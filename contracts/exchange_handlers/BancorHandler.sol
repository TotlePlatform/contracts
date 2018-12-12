pragma solidity 0.4.25;
pragma experimental ABIEncoderV2;

import "../lib/Math.sol";
import "../lib/SafeMath.sol";
import "../lib/AllowanceSetter.sol";
import "../lib/ErrorReporter.sol";
/* import "../lib/Logger.sol"; */
import "./ExchangeHandler.sol";
import "./SelectorProvider.sol";

/// @title BancorConverter
/// @notice Bancor converter contract interface
interface BancorConverter {
    function quickConvert(address[] _path, uint256 _amount, uint256 _minReturn) external payable returns (uint256);
    function registry() external view returns (IContractRegistry);
    function BANCOR_GAS_PRICE_LIMIT() external view returns (bytes32);
    function BANCOR_NETWORK() external view returns (bytes32);
}

/// @title IContractRegistry
/// @notice Bancor contract registry interface
interface IContractRegistry {
    function getAddress(bytes32 _contractName) external view returns (address);
}

/// @title IBancorGasPriceLimit
/// @notice Bancor gas price limit contract interface
interface IBancorGasPriceLimit {
    function gasPrice() external view returns (uint256);
}

/// @title BancorNetwork
/// @notice Bancor Network contract interface
interface BancorNetwork {
    function getReturnByPath(address[] _path, uint256 _amount) external view returns (uint256) ;
}

/// @title BancorSelectorProvider
/// @notice Provides this exchange implementation with correctly formatted function selectors
contract BancorSelectorProvider is SelectorProvider {
    function getSelector(bytes4 genericSelector) public pure returns (bytes4) {
        if (genericSelector == getAmountToGive) {
            return bytes4(keccak256("getAmountToGive((address,address[11],address,uint256,uint256,uint256))"));
        } else if (genericSelector == staticExchangeChecks) {
            return bytes4(keccak256("staticExchangeChecks((address,address[11],address,uint256,uint256,uint256))"));
        } else if (genericSelector == performBuyOrder) {
            return bytes4(keccak256("performBuyOrder((address,address[11],address,uint256,uint256,uint256),uint256)"));
        } else if (genericSelector == performSellOrder) {
            return bytes4(keccak256("performSellOrder((address,address[11],address,uint256,uint256,uint256),uint256)"));
        } else {
            return bytes4(0x0);
        }
    }
}

/// @title Interface for all exchange handler contracts
/// @notice Handles the all Bancor trades for the primary contract
contract BancorHandler is ExchangeHandler, AllowanceSetter {

    /*
    *   Types
    */

    struct OrderData {
        address converterAddress;
        address[11] conversionPath;
        address destinationToken;
        uint256 minReturn;
        uint256 amountToGive;
        uint256 expectedReturn;
    }


    /// @notice Constructor
    /// @param selectorProvider the provider for this exchanges function selectors
    /// @param totlePrimary the address of the totlePrimary contract
    /// @param errorReporter the address of the error reporter contract
    constructor(
        address selectorProvider,
        address totlePrimary,
        address errorReporter
        /* ,address logger */
    )
        ExchangeHandler(selectorProvider, totlePrimary, errorReporter/*, logger*/)
        public
    {}

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
        amountToGive = data.amountToGive;
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
        BancorConverter converter = BancorConverter(data.converterAddress);
        IBancorGasPriceLimit gasPriceLimitContract = IBancorGasPriceLimit(
            converter.registry().getAddress(converter.BANCOR_GAS_PRICE_LIMIT())
        );

        uint256 gasPriceLimit = gasPriceLimitContract.gasPrice();
        checksPassed = tx.gasprice <= gasPriceLimit;

        /* logger.log(
            "Checking gas price arg2: tx.gasprice, arg3: gasPriceLimit",
            tx.gasprice,
            gasPriceLimit
        ); */
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
        amountSpentOnOrder = amountToGiveForOrder;
        amountReceivedFromOrder = BancorConverter(data.converterAddress).quickConvert.value(msg.value)(
            trimAddressArray(data.conversionPath),
            amountToGiveForOrder,
            data.minReturn
        );

        /* logger.log(
            "Performed Bancor buy arg2: amountSpentOnOrder, arg3: amountReceivedFromOrder",
            amountSpentOnOrder,
            amountReceivedFromOrder
        ); */

        if (!ERC20SafeTransfer.safeTransfer(data.destinationToken, totlePrimary, amountReceivedFromOrder)){
            errorReporter.revertTx("Failed to transfer tokens to totle primary");
        }
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
        approveAddress(data.converterAddress, data.conversionPath[0]);

        amountSpentOnOrder = amountToGiveForOrder;
        amountReceivedFromOrder = BancorConverter(data.converterAddress).quickConvert(
            trimAddressArray(data.conversionPath),
            amountToGiveForOrder,
            data.minReturn
        );

        /* logger.log(
            "Performed Bancor sell arg2: amountSpentOnOrder, arg3: amountReceivedFromOrder",
            amountSpentOnOrder,
            amountReceivedFromOrder
        ); */

        totlePrimary.transfer(amountReceivedFromOrder);
    }

    /// @notice Calculate the result of ((numerator * target) / denominator)
    /// @param numerator the numerator in the equation
    /// @param denominator the denominator in the equation
    /// @param target the target for the equations
    /// @return partialAmount the resultant value
    function getPartialAmount(
        uint256 numerator,
        uint256 denominator,
        uint256 target
    )
        internal
        pure
        returns (uint256)
    {
        return SafeMath.div(SafeMath.mul(numerator, target), denominator);
    }

    /// @notice Takes the static array, trims the excess and returns a dynamic array
    /// @param addresses the static array
    /// @return address[] the dynamic array
    function trimAddressArray(address[11] addresses) internal pure returns (address[]) {
        uint256 length = 0;
        for (uint256 index = 0; index < 11; index++){
            if (addresses[index] == 0x0){
                continue;
            }
            length++;
        }
        address[] memory trimmedArray = new address[](length);
        for (index = 0; index < length; index++){
            trimmedArray[index] = addresses[index];
        }
        return trimmedArray;
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
