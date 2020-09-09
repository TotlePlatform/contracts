pragma solidity 0.5.7;
pragma experimental ABIEncoderV2;

import "../lib/ERC20.sol";
import "../lib/SafeMath.sol";
import "../lib/Math.sol";
import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "./ExchangeHandler.sol";


interface IIEarnToken {
    function deposit(uint256 _amount) external;

    function withdraw(uint256 _shares) external;
}


/// @title Handler for IEarnFinance exchange
contract IEarnFinanceHandler is ExchangeHandler, AllowanceSetter {
    /*
     *   Types
     */

    struct OrderData {
        address underlyingToken;
        address iEarnToken;
        bool isRedeem; //True if iEarnToken is source (burn), false if iEarnToken is destination (mint)
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
        IIEarnToken iEarnToken = IIEarnToken(data.iEarnToken);
        ERC20 token = ERC20(data.underlyingToken);
        if (data.isRedeem) {
            amountSpentOnOrder = maxToSpend;
            iEarnToken.withdraw(maxToSpend);
            amountReceivedFromOrder = token.balanceOf(address(this));
            ERC20SafeTransfer.safeTransfer(
                address(token),
                msg.sender,
                amountReceivedFromOrder
            );
        } else {
            approveAddress(address(iEarnToken), address(token));
            amountSpentOnOrder = maxToSpend;
            iEarnToken.deposit(maxToSpend);
            amountReceivedFromOrder = ERC20(address(iEarnToken)).balanceOf(
                address(this)
            );
            ERC20(address(iEarnToken)).transfer(
                msg.sender,
                amountReceivedFromOrder
            );
        }

        if (maxToSpend < availableToSpend) {
            if (data.isRedeem) {
                ERC20(address(iEarnToken)).transfer(
                    msg.sender,
                    availableToSpend - maxToSpend
                );
            } else {
                ERC20SafeTransfer.safeTransfer(
                    address(token),
                    msg.sender,
                    availableToSpend - maxToSpend
                );
            }
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
