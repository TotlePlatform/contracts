// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;
import "../exchange_handlers/ExchangeHandler.sol";

contract KyberMock {
    IERC20 token;

    constructor(address _tokenAddress) {
        token = IERC20(_tokenAddress);
    }


    function tradeWithHint(
        IERC20 src,
        uint256 srcAmount,
        IERC20 dest,
        address destAddress,
        uint256 maxDestAmount,
        uint256 minConversionRate,
        address walletId,
        bytes calldata hint
    ) external payable returns (uint256) {
        src;
        maxDestAmount;
        minConversionRate;
        walletId;
        hint;
        uint256 output;
        if (address(dest) == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            token.transferFrom(msg.sender, address(0x0), srcAmount);
            output = ((srcAmount * 2) * 999) / 1000;
            payable(destAddress).transfer(output);
            return output;
        } else {
            output = ((srcAmount / 2) * 999) / 1000;
            token.transfer(destAddress, output);
            return output;
        }
    }

    fallback() external payable {}

    receive() external payable {}
}
