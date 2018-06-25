pragma solidity 0.4.21;

import { ERC20 as Token } from "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import { SafeMath } from "openzeppelin-solidity/contracts/math/SafeMath.sol";

import { ExchangeHandler } from "./ExchangeHandler.sol";

interface Kyber {
    function trade(Token src, uint srcAmount, Token dest, address destAddress, uint maxDestAmount, uint minConversionRate, address walletId) public payable returns (uint);
}

contract KyberHandler is ExchangeHandler {
    // State variables
    Kyber public exchange;
    Token constant public ETH_TOKEN_ADDRESS = Token(0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);

    // Constructor
    function KyberHandler(address _exchange) public {
        exchange = Kyber(_exchange);
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
        // return amountToGive
        return orderValues[0];
    }

    function performBuy(
        address[8] orderAddresses, // 0: tokenToGet (dest), 1: destAddress (primary), 2: walletId
        uint256[6] orderValues, // 0: srcAmount (amountToGive), 1: dstAmount (amountToGet), 2: maxDestAmount, 3: minConversionRate
        uint256 exchangeFee, // ignore
        uint256 amountToFill, // ignore
        uint8 v, // ignore
        bytes32 r, // ignore
        bytes32 s // ignore
    ) external payable returns (uint256) {
        require(msg.value == orderValues[0]);

        uint256 tokenAmountObtained = trade(
            ETH_TOKEN_ADDRESS, // ERC20 src
            orderValues[0],    // uint srcAmount
            Token(orderAddresses[0]), // ERC20 dest
            orderAddresses[1], // address destAddress (where tokens are sent to after trade)
            orderValues[2],    // uint maxDestAmount
            orderValues[3],    // uint minConversionRate
            orderAddresses[2]  // address walletId
        );

        // If Kyber has sent us back some excess ether
        if(this.balance > 0) {
            msg.sender.transfer(this.balance);
        }

        return tokenAmountObtained;
    }

    function performSell(
        address[8] orderAddresses, // 0: tokenToGive (src), 1: destAddress (primary), 2: walletId
        uint256[6] orderValues, // 0: srcAmount (amountToGive), 1: dstAmount (amountToGet), 2: maxDestAmount, 3: minConversionRate
        uint256 exchangeFee, // ignore
        uint256 amountToFill, // ignore
        uint8 v, // ignore
        bytes32 r, // ignore
        bytes32 s // ignore
    ) external returns (uint256) {

        require(Token(orderAddresses[0]).approve(address(exchange), orderValues[0]));

        uint256 etherAmountObtained = trade(
            Token(orderAddresses[0]), // ERC20 src
            orderValues[0],    // uint srcAmount
            ETH_TOKEN_ADDRESS, // ERC20 dest
            orderAddresses[1], // address destAddress (where tokens are sent to after trade)
            orderValues[2],    // uint maxDestAmount
            orderValues[3],    // uint minConversionRate
            orderAddresses[2]  // address walletId
        );

        return etherAmountObtained;
    }

    function trade(
        Token src,
        uint srcAmount,
        Token dest,
        address destAddress,
        uint maxDestAmount,
        uint minConversionRate,
        address walletId
    ) internal returns (uint256) {
        uint256 valToSend = 0;
        if(src == ETH_TOKEN_ADDRESS) {
            valToSend = srcAmount;
        }

        return exchange.trade.value(valToSend)(
            src,
            srcAmount,
            dest,
            destAddress,
            maxDestAmount,
            minConversionRate,
            walletId
        );
    }

    function() public payable {
        require(msg.sender == address(exchange));
    }
}
