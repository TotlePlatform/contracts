// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IContractRegistry {
    function addressOf(bytes32 _contractName) external view returns (address);
}

/*
    Bancor Converter Mock v0.10

    A mock version of the Bancor Converter that implements the valid functions required for
*/
contract BancorMock {
    address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    IERC20 token;

    constructor(address _tokenAddress) {
        token = IERC20(_tokenAddress);
    }

    function convertByPath2(
        address[] calldata _path,
        uint256 _amount,
        uint256 _minReturn
    ) external payable returns (uint256) {
        _minReturn;
        uint256 output;
        if (
            _path[_path.length - 1] ==
            0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
        ) {
            token.transferFrom(msg.sender, address(0x0), _amount);
            output = ((_amount * 2) * 999) / 1000;

            payable(msg.sender).transfer(output);
            return output;
        } else {
            output = ((_amount / 2) * 999) / 1000;
            token.transfer(msg.sender, output);
            return output;
        }
    }

    fallback() external payable {}

    receive() external payable {}
}
