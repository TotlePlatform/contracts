pragma solidity 0.5.7;

import "./ERC20.sol";
import "./ERC20SafeTransfer.sol";
/// @title A contract which is used to check and set allowances of tokens
/// @dev In order to use this contract is must be inherited in the contract which is using
/// its functionality
contract AllowanceSetter {
    uint256 constant MAX_UINT = 2**256 - 1;

    /// @notice A function which allows the caller to approve the max amount of any given token
    /// @dev In order to function correctly, token allowances should not be set anywhere else in
    /// the inheriting contract
    /// @param addressToApprove the address which we want to approve to transfer the token
    /// @param token the token address which we want to call approve on
    function approveAddress(address addressToApprove, address token) internal {
        if(ERC20(token).allowance(address(this), addressToApprove) == 0) {
            require(ERC20SafeTransfer.safeApprove(token, addressToApprove, MAX_UINT));
        }
    }

}
