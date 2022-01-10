// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "../lib/Withdrawable.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Interface for all exchange handler contracts
abstract contract ExchangeHandler is Withdrawable {
    /*
     *   Public functions
     */

    /// @dev Fills the input order.
    /// @param genericPayload Encoded data for this order. This is specific to exchange and is done by encoding a per-exchange struct
    /// @param availableToSpend The amount of assets that are available for the handler to spend.
    /// @param targetAmount The target for amount of assets to spend - it may spend less than this and return the change.
    /// @return amountSpentOnOrder The amount of source asset spent on this order.
    /// @return amountReceivedFromOrder The amount of destination asset received from this order.

    function performOrder(
        bytes memory genericPayload,
        uint256 availableToSpend,
        uint256 targetAmount
    )
        external
        payable
        virtual
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder);


    /// @notice payable receive  to block EOA sending eth
    /// @dev this should fail if an EOA (or contract with 0 bytecode size) tries to send ETH to this contract
    receive() external payable {
        // Check in here that the sender is a contract! (to stop accidents)
        uint256 size;
        address sender = msg.sender;
        assembly {
            size := extcodesize(sender)
        }
        require(size > 0);
    }
    /* 
     *   Internal functions
     */

    /// @dev Gets the max to spend by taking min of targetAmount and availableToSpend.
    /// @param targetAmount The amount the primary wants this handler to spend
    /// @param availableToSpend The amount the exchange handler has available to spend.
    /// @return max The maximum amount the handler can spend

    function getMaxToSpend(uint256 targetAmount, uint256 availableToSpend)
        internal
        pure
        returns (uint256 max)
    {
        max = Math.min(availableToSpend, targetAmount);
        return max;
    }
}
