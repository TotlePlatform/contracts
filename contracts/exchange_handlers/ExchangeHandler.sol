pragma solidity 0.4.25;
pragma experimental ABIEncoderV2;

import "../lib/TotleControl.sol";
import "../lib/Withdrawable.sol";
import "../lib/Pausable.sol";
import "../lib/ErrorReporter.sol";
/* import "../lib/Logger.sol"; */
import "./SelectorProvider.sol";

/// @title Interface for all exchange handler contracts
contract ExchangeHandler is SelectorProvider, TotleControl, Withdrawable, Pausable {

    /*
    *   State Variables
    */

    ErrorReporter public errorReporter;
    /* Logger public logger; */
    /*
    *   Modifiers
    */

    /// @notice Constructor
    /// @dev Calls the constructor of the inherited TotleControl
    /// @param totlePrimary the address of the totlePrimary contract
    constructor(
        address totlePrimary,
        address _errorReporter
        /* ,address _logger */
    )
        TotleControl(totlePrimary)
        public
    {
        require(_errorReporter != address(0x0));
        /* require(_logger != address(0x0)); */
        errorReporter = ErrorReporter(_errorReporter);
        /* logger = Logger(_logger); */
    }

    /// @notice Gets the amount that Totle needs to give for this order
    /// @param genericPayload the data for this order in a generic format
    /// @return amountToGive amount taker needs to give in order to fill the order
    function getAmountToGive(
        bytes genericPayload
    )
        public
        view
        returns (uint256 amountToGive)
    {
        bool success;
        bytes4 functionSelector = getSelector(this.getAmountToGive.selector);

        assembly {
            let functionSelectorLength := 0x04
            let functionSelectorOffset := 0x1C
            let scratchSpace := 0x0
            let wordLength := 0x20
            let bytesLength := mload(genericPayload)
            let totalLength := add(functionSelectorLength, bytesLength)
            let startOfNewData := add(genericPayload, functionSelectorOffset)

            mstore(add(scratchSpace, functionSelectorOffset), functionSelector)
            let functionSelectorCorrect := mload(scratchSpace)
            mstore(genericPayload, functionSelectorCorrect)

            success := delegatecall(
                            gas,
                            address, // This address of the current contract
                            startOfNewData, // Start data at the beginning of the functionSelector
                            totalLength, // Total length of all data, including functionSelector
                            scratchSpace, // Use the first word of memory (scratch space) to store our return variable.
                            wordLength // Length of return variable is one word
                           )
            amountToGive := mload(scratchSpace)
            if eq(success, 0) { revert(0, 0) }
        }
    }

    /// @notice Perform exchange-specific checks on the given order
    /// @dev this should be called to check for payload errors
    /// @param genericPayload the data for this order in a generic format
    /// @return checksPassed value representing pass or fail
    function staticExchangeChecks(
        bytes genericPayload
    )
        public
        view
        returns (bool checksPassed)
    {
        bool success;
        bytes4 functionSelector = getSelector(this.staticExchangeChecks.selector);
        assembly {
            let functionSelectorLength := 0x04
            let functionSelectorOffset := 0x1C
            let scratchSpace := 0x0
            let wordLength := 0x20
            let bytesLength := mload(genericPayload)
            let totalLength := add(functionSelectorLength, bytesLength)
            let startOfNewData := add(genericPayload, functionSelectorOffset)

            mstore(add(scratchSpace, functionSelectorOffset), functionSelector)
            let functionSelectorCorrect := mload(scratchSpace)
            mstore(genericPayload, functionSelectorCorrect)

            success := delegatecall(
                            gas,
                            address, // This address of the current contract
                            startOfNewData, // Start data at the beginning of the functionSelector
                            totalLength, // Total length of all data, including functionSelector
                            scratchSpace, // Use the first word of memory (scratch space) to store our return variable.
                            wordLength // Length of return variable is one word
                           )
            checksPassed := mload(scratchSpace)
            if eq(success, 0) { revert(0, 0) }
        }
    }

    /// @notice Perform a buy order at the exchange
    /// @param genericPayload the data for this order in a generic format
    /// @param  amountToGiveForOrder amount that should be spent on this order
    /// @return amountSpentOnOrder the amount that would be spent on the order
    /// @return amountReceivedFromOrder the amount that was received from this order
    function performBuyOrder(
        bytes genericPayload,
        uint256 amountToGiveForOrder
    )
        public
        payable
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        bool success;
        bytes4 functionSelector = getSelector(this.performBuyOrder.selector);
        assembly {
            let callDataOffset := 0x44
            let functionSelectorOffset := 0x1C
            let functionSelectorLength := 0x04
            let scratchSpace := 0x0
            let wordLength := 0x20
            let startOfFreeMemory := mload(0x40)

            calldatacopy(startOfFreeMemory, callDataOffset, calldatasize)

            let bytesLength := mload(startOfFreeMemory)
            let totalLength := add(add(functionSelectorLength, bytesLength), wordLength)

            mstore(add(scratchSpace, functionSelectorOffset), functionSelector)

            let functionSelectorCorrect := mload(scratchSpace)

            mstore(startOfFreeMemory, functionSelectorCorrect)

            mstore(add(startOfFreeMemory, add(wordLength, bytesLength)), amountToGiveForOrder)

            let startOfNewData := add(startOfFreeMemory,functionSelectorOffset)

            success := delegatecall(
                            gas,
                            address, // This address of the current contract
                            startOfNewData, // Start data at the beginning of the functionSelector
                            totalLength, // Total length of all data, including functionSelector
                            scratchSpace, // Use the first word of memory (scratch space) to store our return variable.
                            mul(wordLength, 0x02) // Length of return variables is two words
                          )
            amountSpentOnOrder := mload(scratchSpace)
            amountReceivedFromOrder := mload(add(scratchSpace, wordLength))
            if eq(success, 0) { revert(0, 0) }
        }
    }

    /// @notice Perform a sell order at the exchange
    /// @param genericPayload the data for this order in a generic format
    /// @param  amountToGiveForOrder amount that should be spent on this order
    /// @return amountSpentOnOrder the amount that would be spent on the order
    /// @return amountReceivedFromOrder the amount that was received from this order
    function performSellOrder(
        bytes genericPayload,
        uint256 amountToGiveForOrder
    )
        public
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        bool success;
        bytes4 functionSelector = getSelector(this.performSellOrder.selector);
        assembly {
            let callDataOffset := 0x44
            let functionSelectorOffset := 0x1C
            let functionSelectorLength := 0x04
            let scratchSpace := 0x0
            let wordLength := 0x20
            let startOfFreeMemory := mload(0x40)

            calldatacopy(startOfFreeMemory, callDataOffset, calldatasize)

            let bytesLength := mload(startOfFreeMemory)
            let totalLength := add(add(functionSelectorLength, bytesLength), wordLength)

            mstore(add(scratchSpace, functionSelectorOffset), functionSelector)

            let functionSelectorCorrect := mload(scratchSpace)

            mstore(startOfFreeMemory, functionSelectorCorrect)

            mstore(add(startOfFreeMemory, add(wordLength, bytesLength)), amountToGiveForOrder)

            let startOfNewData := add(startOfFreeMemory,functionSelectorOffset)

            success := delegatecall(
                            gas,
                            address, // This address of the current contract
                            startOfNewData, // Start data at the beginning of the functionSelector
                            totalLength, // Total length of all data, including functionSelector
                            scratchSpace, // Use the first word of memory (scratch space) to store our return variable.
                            mul(wordLength, 0x02) // Length of return variables is two words
                          )
            amountSpentOnOrder := mload(scratchSpace)
            amountReceivedFromOrder := mload(add(scratchSpace, wordLength))
            if eq(success, 0) { revert(0, 0) }
        }
    }
}
