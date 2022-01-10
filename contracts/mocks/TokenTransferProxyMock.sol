// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TokenTransferProxyMock {

    function transferFrom(
        address token,
        address from,
        address to,
        uint value)
        public
        returns (bool)
    {
        SafeERC20.safeTransferFrom(IERC20(token), from, to, value);
        return true;
    }

}
