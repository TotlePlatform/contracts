pragma solidity 0.4.21;

import { ERC20 as Token } from "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import { SafeMath } from "openzeppelin-solidity/contracts/math/SafeMath.sol";

import { ExchangeHandler } from "./ExchangeHandler.sol";

import { ZeroExExchange } from './ZeroExExchange.sol';

interface DepositToken {
    function deposit() external payable;
    function withdraw(uint amount) external payable;
    function balanceOf(address who) external returns(uint256);
}

contract ZeroExHandler is ExchangeHandler {
    address wethAddress;
    address public exchangeAddress;
    uint constant MAX_UINT = 2**256 - 1;
    mapping(address => bool) public tokenAllowanceSet;

    event Order(
        address[8] addrs,
        uint256[6] values,
        uint256 value,
        address exc
    );

    function ZeroExHandler(address _exchangeAddr, address _wethAddr) public {
        exchangeAddress = _exchangeAddr;
        wethAddress = _wethAddr;
    }

    function() public payable { }

    /*
     * Returns the remaining amount of the taker token available from this
     * order.
     */
    function getAvailableAmount(
        address[8] orderAddresses,
        uint256[6] orderValues,
        uint256 exchangeFee,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256) {
        if (!orderUsable(orderAddresses, orderValues)) {
            return 0;
        }
        address[5] memory newAddresses = convertAddressFormat(orderAddresses);
        bytes32 orderHash = ZeroExExchange(exchangeAddress).getOrderHash(newAddresses, orderValues);
        return SafeMath.sub(orderValues[1], ZeroExExchange(exchangeAddress).getUnavailableTakerTokenAmount(orderHash));
    }

    /*
     * Spend ETH to acquire tokens
     */
    function performBuy(
        address[8] orderAddresses,
        uint256[6] orderValues,
        uint256 exchangeFee,
        uint256 amountToFill,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable returns (uint256) {
        require(orderUsable(orderAddresses, orderValues));
        require(orderAddresses[3] == wethAddress);
        require(amountToFill == msg.value);
        DepositToken(wethAddress).deposit.value(amountToFill)();
        address[5] memory newAddresses = convertAddressFormat(orderAddresses);
        bytes32 orderHash = ZeroExExchange(exchangeAddress).getOrderHash(newAddresses, orderValues);
        setAllowance(wethAddress);
        ZeroExExchange(exchangeAddress).fillOrder(newAddresses, orderValues, amountToFill, true, v, r, s);
        uint receivedAmount = getPartialAmount(amountToFill, orderValues[1], orderValues[0]);
        require(Token(newAddresses[2]).transfer(msg.sender, receivedAmount));
        return receivedAmount;
    }

    /*
     * Spend tokens to acquire ETH
     */
    function performSell(
        address[8] orderAddresses,
        uint256[6] orderValues,
        uint256 exchangeFee,
        uint256 amountToFill,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256) {
        require(orderUsable(orderAddresses, orderValues));
        require(orderAddresses[2] == wethAddress);
        address[5] memory newAddresses = convertAddressFormat(orderAddresses);
        setAllowance(orderAddresses[3]);
        ZeroExExchange(exchangeAddress).fillOrder(newAddresses, orderValues, amountToFill, false, v, r, s);
        uint receivedAmount = getPartialAmount(amountToFill, orderValues[1], orderValues[0]);
        DepositToken(wethAddress).withdraw(receivedAmount);
        msg.sender.transfer(receivedAmount);
        return receivedAmount;
    }

    function setAllowance(address token) internal {
        if(!tokenAllowanceSet[token]) {
            require(Token(token).approve(ZeroExExchange(exchangeAddress).TOKEN_TRANSFER_PROXY_CONTRACT(), MAX_UINT));
            tokenAllowanceSet[token] = true;
        }
    }

    function orderUsable(
        address[8] orderAddresses,
        uint256[6] orderValues
    ) internal returns (bool) {
        return (
            (orderAddresses[1] == address(0) ||    // Order's taker is anybody
            orderAddresses[1] == address(this)) && // Or the order's taker is this handler
            orderValues[3] == 0 &&                 // takerFees are 0
            orderValues[4] > block.timestamp       // Order is not expired
        );
    }

    function getPartialAmount(uint numerator, uint denominator, uint target)
        public
        constant
        returns (uint)
    {
        return SafeMath.div(SafeMath.mul(numerator, target), denominator);
    }

    function convertAddressFormat(address[8] oldFormat) internal pure returns (address[5] newFormat) {
        for(uint256 i = 0; i < newFormat.length; i++) {
            newFormat[i] = oldFormat[i];
        }
    }
}
