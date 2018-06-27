pragma solidity 0.4.21;

import { ERC20 as Token } from "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import { SafeMath } from "openzeppelin-solidity/contracts/math/SafeMath.sol";

import { ExchangeHandler } from "./ExchangeHandler.sol";

interface EtherDelta {

    function deposit() public payable;

    function withdraw(uint amount) public;

    function depositToken(address token, uint amount) public;

    function withdrawToken(address token, uint amount) public;

    function trade(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce, address user, uint8 v, bytes32 r, bytes32 s, uint amount) public;

    function availableVolume(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce, address user, uint8 v, bytes32 r, bytes32 s) constant returns(uint);
}

contract EtherDeltaHandler is ExchangeHandler {
    // State variables
    EtherDelta public exchange;

    // Constructor
    function EtherDeltaHandler(address _exchange) public {
        exchange = EtherDelta(_exchange);
    }

    // Public functions
    function getAvailableAmount(
        address[8] orderAddresses,
        uint256[6] orderValues,
        uint256 exchangeFee,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256) {

        if(block.number > orderValues[2]) {
            // Order has expired
            return 0;
        }

        uint256 availableVolume = exchange.availableVolume(
            orderAddresses[2],
            orderValues[1],
            orderAddresses[1],
            orderValues[0],
            orderValues[2],
            orderValues[3],
            orderAddresses[0],
            v,
            r,
            s
        );

        // Adds the exchange fee onto the available amount
        return getPartialAmount(availableVolume, SafeMath.sub(1 ether, exchangeFee), 1 ether);
    }

    function performBuy(
        address[8] orderAddresses,
        uint256[6] orderValues,
        uint256 exchangeFee,
        uint256 amountToFill,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable returns (uint256) {
        require(msg.value == amountToFill);

        deposit(amountToFill);

        uint256 amountToTrade;
        uint256 fee;

        (amountToTrade, fee) = substractFee(exchangeFee, amountToFill);

        trade(
            orderAddresses,
            orderValues,
            amountToTrade,
            v,
            r,
            s
        );

        uint256 tokenAmountObtained = getPartialAmount(orderValues[0], orderValues[1], amountToTrade);

        withdrawToken(orderAddresses[1], tokenAmountObtained);
        transferTokenToSender(orderAddresses[1], tokenAmountObtained);

        return tokenAmountObtained;
    }

    function performSell(
        address[8] orderAddresses,
        uint256[6] orderValues,
        uint256 exchangeFee,
        uint256 amountToFill,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256) {
        depositToken(orderAddresses[2], amountToFill);

        uint256 amountToTrade;
        uint256 fee;

        (amountToTrade, fee) = substractFee(exchangeFee, amountToFill);

        trade(
            orderAddresses,
            orderValues,
            amountToTrade,
            v,
            r,
            s
        );

        uint256 etherAmountObtained = getPartialAmount(orderValues[0], orderValues[1], amountToTrade);

        withdraw(etherAmountObtained);
        transferEtherToSender(etherAmountObtained);

        return etherAmountObtained;
    }

    // Internal functions
    function trade(
        address[8] orderAddresses,
        uint256[6] orderValues,
        uint256 amountToTrade,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        exchange.trade(
            orderAddresses[2],
            orderValues[1],
            orderAddresses[1],
            orderValues[0],
            orderValues[2],
            orderValues[3],
            orderAddresses[0],
            v,
            r,
            s,
            amountToTrade
        );
    }

    function substractFee(uint256 feePercentage, uint256 amount) internal pure returns (uint256, uint256) {
        uint256 fee = getPartialAmount(amount, 1 ether, feePercentage);
        return (SafeMath.sub(amount, fee), fee);
    }

    function deposit(uint256 amount) internal {
        exchange.deposit.value(amount)();
    }

    function depositToken(address token, uint256 amount) internal {
        require(Token(token).approve(address(exchange), amount));
        exchange.depositToken(token, amount);
    }

    function withdraw(uint256 amount) internal {
        exchange.withdraw(amount);
    }

    function withdrawToken(address token, uint256 amount) internal {
        exchange.withdrawToken(token, amount);
    }

    function transferTokenToSender(address token, uint256 amount) internal {
        require(Token(token).transfer(msg.sender, amount));
    }

    function transferEtherToSender(uint256 amount) internal {
        msg.sender.transfer(amount);
    }

    function getPartialAmount(uint256 numerator, uint256 denominator, uint256 target) internal pure returns (uint256) {
        return SafeMath.div(SafeMath.mul(numerator, target), denominator);
    }

    function() public payable {
        require(msg.sender == address(exchange));
    }
}
