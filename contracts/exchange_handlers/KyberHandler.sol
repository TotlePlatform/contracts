pragma solidity 0.5.7;
pragma experimental ABIEncoderV2;

import "../lib/ERC20.sol";
import "../lib/SafeMath.sol";
import "../lib/Math.sol";
import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "./ExchangeHandler.sol";

interface Kyber {
    function tradeWithHint(
        ERC20 src,
        uint256 srcAmount,
        ERC20 dest,
        address destAddress,
        uint256 maxDestAmount,
        uint256 minConversionRate,
        address walletId,
        bytes calldata hint
    ) external payable returns (uint256);
    function maxGasPrice() external view returns(uint);

    function trade(
        ERC20 src,
        uint256 srcAmount,
        ERC20 dest,
        address destAddress,
        uint256 maxDestAmount,
        uint256 minConversionRate,
        address walletId
    ) external payable returns (uint256);
}

/// @title Interface for all exchange handler contracts
contract KyberHandler is ExchangeHandler, AllowanceSetter {
    /*
     *   State Variables
     */
    Kyber public constant exchange = Kyber(
        0x9AAb3f75489902f3a48495025729a0AF77d4b11e
    );
    address ETH_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    /*
     *   Types
     */

    struct OrderData {
        address tokenFrom;
        address tokenTo;
        uint256 maxSpend;
        bytes hint;
    }

    /// @notice Constructor
    constructor() public {}

    /*
     *   Internal functions
     */

    /// @notice Perform exchange-specific checks on the given order
    /// @dev This should be called to check for payload errors
    /// @param data OrderData struct containing order values
    /// @return checksPassed value representing pass or fail
    function staticExchangeChecks(OrderData memory data)
        public
        view
        returns (bool checksPassed)
    {
        uint256 maxGasPrice = exchange.maxGasPrice();

        return (maxGasPrice >= tx.gasprice);
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
        uint256 originalBalance = getBalance(data.tokenFrom);
        if (!staticExchangeChecks(data)) {
            if (data.tokenFrom == Utils.eth_address()) {
                msg.sender.transfer(msg.value);
            } else {
                ERC20SafeTransfer.safeTransfer(
                    data.tokenFrom,
                    msg.sender,
                    availableToSpend
                );
            }
        }
        approve(address(exchange), data.tokenFrom);
        uint256 amountToSpend = Math.min(
            Math.min(
                availableToSpend,
                targetAmountIsSource ? targetAmount : availableToSpend
            ),
            data.maxSpend
        );
        amountReceivedFromOrder = exchange.tradeWithHint.value(
            data.tokenFrom == Utils.eth_address() ? amountToSpend : 0
        )(
            ERC20(
                data.tokenFrom == Utils.eth_address()
                    ? ETH_TOKEN_ADDRESS
                    : data.tokenFrom
            ),
            amountToSpend,
            ERC20(
                data.tokenTo == Utils.eth_address()
                    ? ETH_TOKEN_ADDRESS
                    : data.tokenTo
            ),
            msg.sender,
            targetAmountIsSource ? Utils.max_uint() : targetAmount,
            1,
            address(0x583d03451406d179182efc742A1d811a9e34C36b),
            data.hint
        );
        uint256 newInputBalance = getBalance(data.tokenFrom);
        amountSpentOnOrder = originalBalance - newInputBalance;
        if (amountSpentOnOrder < availableToSpend) {
            if (data.tokenFrom == Utils.eth_address()) {
                msg.sender.transfer(
                    SafeMath.sub(availableToSpend, amountSpentOnOrder)
                );
            } else {
                ERC20SafeTransfer.safeTransfer(
                    data.tokenFrom,
                    msg.sender,
                    SafeMath.sub(availableToSpend, amountSpentOnOrder)
                );
            }
        }
    }

    function approve(address spender, address token) internal {
        if (token != Utils.eth_address()) {
            approveAddress(spender, token);
        }
    }

    function getBalance(address token) internal returns (uint256 balance) {
        if (token == Utils.eth_address()) {
            return address(this).balance;
        } else {
            return ERC20(token).balanceOf(address(this));
        }
    }

    function transfer(address token, uint256 amount) internal {
        if (token == Utils.eth_address()) {
            msg.sender.transfer(amount);
        } else {
            ERC20SafeTransfer.safeTransfer(token, msg.sender, amount);
        }
    }

    /// @notice payable fallback to block EOA sending eth
    /// @dev this should fail if an EOA (or contract with 0 bytecode size) tries to send ETH to this contract
    function() external payable {
    }
}
