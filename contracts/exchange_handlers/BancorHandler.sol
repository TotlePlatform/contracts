pragma solidity 0.5.7;
pragma experimental ABIEncoderV2;

import "../lib/Math.sol";
import "../lib/SafeMath.sol";
import "../lib/SafeMath.sol";
import "../lib/AllowanceSetter.sol";
import "../lib/Utils.sol";
import "./ExchangeHandler.sol";

/// @title BancorConverter
/// @notice Bancor converter contract interface
interface BancorConverter {
    function quickConvert(address[] calldata _path, uint256 _amount, uint256 _minReturn) external payable returns (uint256);
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
    function getReturnByPath(address[] calldata _path, uint256 _amount) external view returns (uint256) ;
}

/// @title Interface for all exchange handler contracts
/// @notice Handles the all Bancor trades for the primary contract
contract BancorHandler is ExchangeHandler, AllowanceSetter {

    /*
    *   Types
    */

    struct OrderData {
        address converterAddress;
        address[5] conversionPath;
        address destinationToken;
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
            if(msg.value > 0){
                msg.sender.transfer(msg.value);
            } else {
                ERC20SafeTransfer.safeTransfer(data.conversionPath[0], msg.sender, availableToSpend);
            }
        }
        approve(data.converterAddress, data.conversionPath[0]);
        amountSpentOnOrder = Math.min(availableToSpend, targetAmount);
        amountReceivedFromOrder = BancorConverter(data.converterAddress).quickConvert.value(msg.value)(
            trimAddressArray(data.conversionPath),
            amountSpentOnOrder,
            1
        );
        if(amountSpentOnOrder < availableToSpend){
            if(msg.value > 0){
                msg.sender.transfer(SafeMath.sub(availableToSpend, amountSpentOnOrder));
            } else {
                ERC20SafeTransfer.safeTransfer(data.conversionPath[0], msg.sender, SafeMath.sub(availableToSpend, amountSpentOnOrder));
            }
        }
        if(data.destinationToken == Utils.eth_address()){
            msg.sender.transfer(amountReceivedFromOrder);
        } else {
            ERC20SafeTransfer.safeTransfer(data.destinationToken, msg.sender, amountReceivedFromOrder);
        }
    }


    /// @notice Takes the static array, trims the excess and returns a dynamic array
    /// @param addresses the static array
    /// @return address[] the dynamic array
    function trimAddressArray(address[5] memory addresses) internal pure returns (address[] memory) {
        uint256 length = 0;
        uint256 index = 0;
        for (index = 0; index < 5; index++){
            if (addresses[index] == address(0x0)){
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

    function approve(
        address spender,
        address token
    )
        internal 
    {
        if(msg.value == 0){
            approveAddress(spender, token);
        }
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
        require(size > 0, "EOA cannot send ether to bancor fallback");
    }
}
