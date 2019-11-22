pragma solidity 0.5.7;
pragma experimental ABIEncoderV2;

import "../lib/ERC20.sol";
import "../lib/SafeMath.sol";
import "../lib/Math.sol";
import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "./ExchangeHandler.sol";



contract IToken is ERC20 {
    function mint(address receiver, uint depositAmount) external returns (uint);
    function burn(address receiver, uint withdrawAmount) external returns (uint);
    function mintWithEther(address receiver) external payable returns (uint);
    function burnToEther(address receiver, uint256 withdrawAmount) external returns (uint);
    function loanTokenAddress() external returns (address);
}


/// @title Handler for Fulcrum exchange
contract FulcrumHandler is ExchangeHandler, AllowanceSetter {

    address public weth;
    /*
    *   Types
    */

    struct OrderData {
        address iToken;
        bool isSourceIToken; //True if IToken is source (burn), false if IToken is destination (mint)
    }

    /// @notice Constructor
    /// @param _weth Address of the weth token
    constructor(
        address _weth
    )
        public
    {
        weth = _weth;
    }

    function performOrder(
        bytes memory genericPayload,
        uint256 availableToSpend,
        uint256 targetAmount,
        bool targetAmountIsSource
    )
        public
        payable
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        OrderData memory data = abi.decode(genericPayload, (OrderData));
        uint256 maxToSpend = getMaxToSpend(targetAmountIsSource, targetAmount, availableToSpend);
        IToken iToken = IToken(data.iToken);
        ERC20 token = ERC20(iToken.loanTokenAddress());
        if(data.isSourceIToken){
            amountSpentOnOrder = maxToSpend;
            if(address(token) == weth){
                amountReceivedFromOrder = iToken.burnToEther(msg.sender, maxToSpend);
            } else {
                amountReceivedFromOrder = iToken.burn(msg.sender, maxToSpend);
            }
        } else {
            approveAddress(address(iToken), address(token));
            amountSpentOnOrder = maxToSpend;
            if(address(token) == weth){
                amountReceivedFromOrder = iToken.mintWithEther.value(amountSpentOnOrder)(msg.sender);
            } else {
                amountReceivedFromOrder = iToken.mint(msg.sender, maxToSpend);
            }
        }
    }

    function getMaxToSpend(
        bool targetAmountIsSource,
        uint256 targetAmount,
        uint256 availableToSpend
    )
        internal
        returns (uint256 max)
    {
        max = availableToSpend;
        if(targetAmountIsSource){
            max = Math.min(max, targetAmount);
        }
        return max;
    }

  

    /// @notice payable fallback to block EOA sending eth
    /// @dev this should fail if an EOA (or contract with 0 bytecode size) tries to send ETH to this contract
    function() external payable {
        // Check in here that the sender is a contract! (to stop accidents)
        uint256 size;
        address sender = msg.sender;
        assembly {
            size := extcodesize(sender)
        }
        require(size > 0);
    }
}
