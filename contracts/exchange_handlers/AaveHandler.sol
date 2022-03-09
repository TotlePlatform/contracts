// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "./ExchangeHandler.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface LendingPool {
    function deposit(
        address sourceToken,
        uint256 sourceAmount,
        uint16 referralCode
    ) external payable;
}

abstract contract AToken is IERC20 {
    function redeem(uint256 amount) external virtual;
}

/// @title Handler for Aave exchange
contract AaveHandler is ExchangeHandler, AllowanceSetter {
    /*
     *   Constants
     */
    address constant A_ETH =
        address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    /*
     *   Types
     */

    struct OrderData {
        bool isDeposit;
        address lendingPool;
        address core;
        IERC20 underlyingToken;
        IERC20 aToken;
        uint256 maxSpend;
    }

    /*
     *   Public functions
     */

    function performOrder(
        bytes memory genericPayload,
        uint256 availableToSpend,
        uint256 targetAmount
    )
        public
        override
        payable
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        OrderData memory data = abi.decode(genericPayload, (OrderData));
        uint256 maxToSpend = getMaxToSpend(
            targetAmount,
            Math.min(availableToSpend, data.maxSpend)
        );
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
                    data.underlyingToken,
                    data.aToken,
                    maxToSpend
                );
        }
    }

    /*
     *   Internal functions
     */

    function performDepositAction(
        LendingPool lendingPool,
        address core,
        IERC20 underlyingToken,
        IERC20 aToken,
        uint256 maxToSpend
    )
        internal
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        if (address(underlyingToken) != A_ETH) {
            approveAddress(address(core), address(underlyingToken));
        }
        amountSpentOnOrder = maxToSpend;
        amountReceivedFromOrder = maxToSpend;

        lendingPool.deposit{value: address(underlyingToken) == A_ETH ? maxToSpend : 0}(
            address(underlyingToken),
            maxToSpend,
            0
        );
        SafeERC20.safeTransfer(aToken, msg.sender, amountReceivedFromOrder);
    }

    function performWithdrawAction(
        IERC20 underlyingToken,
        IERC20 aToken,
        uint256 maxToSpend
    )
        internal
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        amountSpentOnOrder = maxToSpend;
        amountReceivedFromOrder = maxToSpend;
        AToken(address(aToken)).redeem(maxToSpend);
        if (address(underlyingToken) == A_ETH) {
            payable(msg.sender).transfer(maxToSpend);
        } else {
            SafeERC20.safeTransfer(
                underlyingToken,
                msg.sender,
                amountReceivedFromOrder
            );
        }
    }

}
