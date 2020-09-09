pragma solidity 0.5.7;
pragma experimental ABIEncoderV2;

import "../lib/ERC20.sol";
import "../lib/ERC20SafeTransfer.sol";
import "../lib/SafeMath.sol";
import "../lib/Math.sol";
import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "./ExchangeHandler.sol";

contract LendingPool {
    function deposit(
        address sourceToken,
        uint256 sourceAmount,
        uint16 referralCode
    ) external payable;

    function redeemUnderlying(
        address destinationToken,
        address recipient,
        uint256 sourceAmount,
        uint256
    ) external;
}

contract AToken is ERC20 {
    function redeem(uint256 amount) external;
}

/// @title Handler for Aave exchange
contract AaveHandler is ExchangeHandler, AllowanceSetter {
    /*
    *   Constants
    */
    address constant A_ETH = address(
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
    );

    /*
    *   Types
    */

    struct OrderData {
        bool isDeposit;
        address lendingPool;
        address core;
        address underlyingToken;
        address aToken;
        uint256 maxSpend;
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
            availableToSpend,
            data.maxSpend
        );
        if (maxToSpend < availableToSpend) {
            if (data.underlyingToken == A_ETH) {
                msg.sender.transfer(availableToSpend - maxToSpend);
            } else {
                require(
                    ERC20SafeTransfer.safeTransfer(
                        data.underlyingToken,
                        msg.sender,
                        availableToSpend - maxToSpend
                    ),
                    "AaveHandler:Transfer Failed"
                );

            }
        }
        if (data.isDeposit) {
            return
                performDepositAction(
                    LendingPool(data.lendingPool),
                    data.core,
                    data.underlyingToken,
                    data.aToken,
                    maxToSpend
                );
        } else {
            return
                performWithdrawAction(
                    LendingPool(data.lendingPool),
                    data.core,
                    data.underlyingToken,
                    data.aToken,
                    maxToSpend
                );
        }
    }

    function performDepositAction(
        LendingPool lendingPool,
        address core,
        address underlyingToken,
        address aToken,
        uint256 maxToSpend
    )
        internal
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        if (underlyingToken != A_ETH) {
            approveAddress(address(core), underlyingToken);
        }
        lendingPool.deposit.value(underlyingToken == A_ETH ? maxToSpend : 0)(
            underlyingToken,
            maxToSpend,
            0
        );
        amountSpentOnOrder = maxToSpend;
        amountReceivedFromOrder = maxToSpend;
        require(
            ERC20SafeTransfer.safeTransfer(
                aToken,
                msg.sender,
                amountReceivedFromOrder
            ),
            "AaveHandler:Transfer Failed"
        );
    }

    function performWithdrawAction(
        LendingPool lendingPool,
        address core,
        address underlyingToken,
        address aToken,
        uint256 maxToSpend
    )
        internal
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        AToken(aToken).redeem(maxToSpend);
        amountSpentOnOrder = maxToSpend;
        amountReceivedFromOrder = maxToSpend;
        if (underlyingToken == A_ETH) {
            msg.sender.transfer(maxToSpend);
        } else {
            require(
                ERC20SafeTransfer.safeTransfer(
                    underlyingToken,
                    msg.sender,
                    amountReceivedFromOrder
                ),
                "AaveHandler:Transfer Failed"
            );
        }
    }

    function getMaxToSpend(
        bool targetAmountIsSource,
        uint256 targetAmount,
        uint256 availableToSpend,
        uint256 maxOrderSpend
    ) internal returns (uint256 max) {
        max = availableToSpend;
        if (targetAmountIsSource) {
            max = Math.min(Math.min(max, targetAmount), maxOrderSpend);
        }
        return max;
    }

    function() external payable {}
}
