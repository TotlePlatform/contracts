pragma solidity 0.4.25;

import "./Ownable.sol";

/// @title A contract which can be used to ensure only the TotlePrimary contract can call
/// some functions
/// @dev Defines a modifier which should be used when only the totle contract should
/// able able to call a function
contract TotleControl is Ownable {
    address public totlePrimary;

    /// @dev A modifier which only allows code execution if msg.sender equals totlePrimary address
    modifier onlyTotle() {
        require(msg.sender == totlePrimary);
        _;
    }

    /// @notice Contract constructor
    /// @dev As this contract inherits ownable, msg.sender will become the contract owner
    /// @param _totlePrimary the address of the contract to be set as totlePrimary
    constructor(address _totlePrimary) public {
        require(_totlePrimary != address(0x0));
        totlePrimary = _totlePrimary;
    }

    /// @notice A function which allows only the owner to change the address of totlePrimary
    /// @dev onlyOwner modifier only allows the contract owner to run the code
    /// @param _totlePrimary the address of the contract to be set as totlePrimary
    function setTotle(
        address _totlePrimary
    ) external onlyOwner {
        require(_totlePrimary != address(0x0));
        totlePrimary = _totlePrimary;
    }
}
