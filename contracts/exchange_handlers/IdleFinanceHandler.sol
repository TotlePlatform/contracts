pragma solidity 0.5.7;
pragma experimental ABIEncoderV2;

import "../lib/ERC20.sol";
import "../lib/SafeMath.sol";
import "../lib/Math.sol";
import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "./ExchangeHandler.sol";

interface IIdleToken{
  function mintIdleToken(uint256 _amount, bool _skipWholeRebalance, address _referral) external returns (uint256 mintedTokens);
  function redeemIdleToken(uint256 _amount) external returns (uint256 redeemedTokens);
}
/// @title Handler for IdleFinance exchange
contract IdleFinanceHandler is ExchangeHandler, AllowanceSetter {
    /*
    *   Types
    */

    struct OrderData {
        address underlyingToken;
        address idleToken;
        bool isRedeem; //True if idleToken is source (burn), false if idleToken is destination (mint)
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
        uint256 maxToSpend = getMaxToSpend(
            targetAmountIsSource,
            targetAmount,
            availableToSpend
        );
        IIdleToken idleToken = IIdleToken(data.idleToken);
        ERC20 token = ERC20(data.underlyingToken);
        if (data.isRedeem) {
            amountSpentOnOrder = maxToSpend;
            amountReceivedFromOrder = idleToken.redeemIdleToken(
                maxToSpend
            );
            token.transfer(msg.sender, amountReceivedFromOrder);
        } else {
            approveAddress(address(idleToken), address(token));
            amountSpentOnOrder = maxToSpend;
            amountReceivedFromOrder = idleToken.mintIdleToken(maxToSpend, true, address(0x0000000000000000000000000000000000000000));
            ERC20(address(idleToken)).transfer(msg.sender, amountReceivedFromOrder);
        }
    }

    function getMaxToSpend(
        bool targetAmountIsSource,
        uint256 targetAmount,
        uint256 availableToSpend
    ) internal returns (uint256 max) {
        max = availableToSpend;
        if (targetAmountIsSource) {
            max = Math.min(max, targetAmount);
        }
        return max;
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
