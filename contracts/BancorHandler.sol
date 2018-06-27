pragma solidity 0.4.21;

import { ERC20 as Token } from "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import { ExchangeHandler } from "./ExchangeHandler.sol";

interface BancorConverter {
    function quickConvert(address[] _path, uint256 _amount, uint256 _minReturn) public payable returns (uint256);
}

contract BancorHandler is ExchangeHandler {
    uint256 constant MAX_UINT = 2**256 - 1;
    mapping(address => bool) public tokenAllowanceSet;

    // Public functions
    function getAvailableAmount(
        address[8] orderAddresses, // [converterAddress, conversionPath ... ]
        uint256[6] orderValues, // [amountToGive, minReturn, EMPTY, EMPTY, EMPTY, EMPTY]
        uint256 exchangeFee, // ignore
        uint8 v, // ignore
        bytes32 r, // ignore
        bytes32 s // ignore
    ) external returns (uint256) {
        // Return amountToGive
        return orderValues[0];
    }

    function performBuy(
        address[8] orderAddresses, // [converterAddress, conversionPath ... ]
        uint256[6] orderValues, // [amountToGive, minReturn, EMPTY, EMPTY, EMPTY, EMPTY]
        uint256 exchangeFee, // ignore
        uint256 amountToFill, // ignore
        uint8 v, // ignore
        bytes32 r, // ignore
        bytes32 s // ignore
    ) external payable returns (uint256 amountObtained) {
        address destinationToken;
        (amountObtained, destinationToken) = trade(orderAddresses, orderValues);
        transferTokenToSender(destinationToken, amountObtained);
    }

    function performSell(
        address[8] orderAddresses, // [converterAddress, conversionPath ... ]
        uint256[6] orderValues, // [amountToGive, minReturn, EMPTY, EMPTY, EMPTY, EMPTY]
        uint256 exchangeFee, // ignore
        uint256 amountToFill, // ignore
        uint8 v, // ignore
        bytes32 r, // ignore
        bytes32 s // ignore
    ) external returns (uint256 amountObtained) {
        approveExchange(orderAddresses[0], orderAddresses[1], orderValues[0]);
        (amountObtained, ) = trade(orderAddresses, orderValues);
        transferEtherToSender(amountObtained);
    }

    function trade(
        address[8] orderAddresses, // [converterAddress, conversionPath ... ]
        uint256[6] orderValues // [amountToGive, minReturn, EMPTY, EMPTY, EMPTY, EMPTY]
    ) internal returns (uint256 amountObtained, address destinationToken) {
        // Find the length of the conversion path
        uint256 len;
        for(len = 1; len < orderAddresses.length; len++) {
            if(orderAddresses[len] == 0) {
                require(len > 1);
                destinationToken = orderAddresses[len - 1];
                len--;
                break;
            } else if(len == orderAddresses.length - 1) {
                destinationToken = orderAddresses[len];
                break;
            }
        }
        // Create an array of that length
        address[] memory conversionPath = new address[](len);

        // Move the contents from orderAddresses to conversionPath
        for(uint256 i = 0; i < len; i++) {
            conversionPath[i] = orderAddresses[i + 1];
        }

        amountObtained = BancorConverter(orderAddresses[0])
                            .quickConvert.value(msg.value)(conversionPath, orderValues[0], orderValues[1]);
    }

    function transferTokenToSender(address token, uint256 amount) internal {
        require(Token(token).transfer(msg.sender, amount));
    }

    function transferEtherToSender(uint256 amount) internal {
        msg.sender.transfer(amount);
    }

    function approveExchange(address exchange, address token, uint256 amount) internal {
        if(!tokenAllowanceSet[token]) {
            require(Token(token).approve(exchange, MAX_UINT));
            tokenAllowanceSet[token] = true;
        }
    }

    function() public payable {
    }
}
