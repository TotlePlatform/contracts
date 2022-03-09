// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;
import "../exchange_handlers/ExchangeHandler.sol";

contract UniswapMock {
    IERC20 token;

    constructor(address _tokenAddress) {
        token = IERC20(_tokenAddress);
    }

    function ethToTokenTransferInput(
        uint256 minTokens,
        uint256 deadline,
        address recipient
    ) public payable returns (uint256 bought) {
        // Silence unused parameter warning
        deadline;
        minTokens;
        uint256 numerator = msg.value * token.balanceOf(address(this)) * 997;
        uint256 denominator = (address(this).balance - msg.value) *
            1000 +
            msg.value *
            997;
        uint256 output = numerator / denominator;
        token.transfer(recipient, output);
        return output;
    }

    function tokenToEthTransferInput(
        uint256 input,
        uint256 minEth,
        uint256 deadline,
        address payable recipient
    ) public returns (uint256 bought) {
        // Silence unused parameter warning
        deadline;
        minEth;
        uint256 numerator = input * address(this).balance * 997;
        uint256 denominator = token.balanceOf(address(this)) *
            1000 +
            input *
            997;
        SafeERC20.safeTransferFrom(token, msg.sender, address(this), input);
        bought = numerator / denominator;
        recipient.transfer(bought);
        return bought;
    }

    function getTokenToEthInputPrice(uint256 input)
        public
        view
        returns (uint256 output)
    {
        require(input > 0);
        uint256 numerator = input * address(this).balance * 997;
        uint256 denominator = token.balanceOf(address(this)) *
            1000 +
            input *
            997;
        return numerator / denominator;
    }

    function getTokenToEthOutputPrice(uint256 output)
        public
        view
        returns (uint256 input)
    {
        require(output > 0);
        uint256 numerator = output * token.balanceOf(address(this)) * 1000;
        uint256 denominator = (address(this).balance - output) * 997;
        return numerator / denominator + 1;
    }

    function getEthToTokenOutputPrice(uint256 output)
        public
        view
        returns (uint256 input)
    {
        require(output > 0);
        uint256 numerator = output * address(this).balance * 1000;
        uint256 denominator = (token.balanceOf(address(this)) - output) * 997;
        return numerator / denominator + 1;
    }

    function depositEth() public payable {}

    function tokenAddress() public view returns (address) {
        return address(token);
    }

    function getExchange(address _token) public view returns (address) {
        _token;
        return address(this);
    }
}
