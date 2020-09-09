pragma solidity 0.5.7;
pragma experimental ABIEncoderV2;

import "../lib/ERC20.sol";
import "../lib/SafeMath.sol";
import "../lib/Math.sol";
import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "./ExchangeHandler.sol";

contract PotLike {
    function chi() external returns (uint256);
    function rho() external returns (uint256);
    function drip() external returns (uint256);
}

contract Chai is ERC20 {
    function exit(address src, uint256 chaiAmount) external;
    function join(address dst, uint256 daiAmount) external;
}

/// @title Handler for Chai
contract ChaiHandler is ExchangeHandler, AllowanceSetter {
    /*
    *   Types
    */
    Chai constant CHAI = Chai(0x06AF07097C9Eeb7fD685c692751D5C66dB49c215);
    ERC20 constant DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    PotLike constant POT = PotLike(0x197E90f9FAD81970bA7976f33CbD77088E5D7cf7);

    struct OrderData {
        bool isDeposit;
        uint256 maxSpend;
    }

    /*
    *   Internal functions
    */

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
        uint256 maxToSpend = getMaxToSpend(
            targetAmountIsSource,
            targetAmount,
            availableToSpend,
            data.maxSpend
        );
        if (data.isDeposit) {
            (amountSpentOnOrder, amountReceivedFromOrder) = performJoinAction(
                maxToSpend
            );
        } else {
            (amountSpentOnOrder, amountReceivedFromOrder) = performExitAction(
                maxToSpend
            );
        }
        if (maxToSpend < availableToSpend) {
            if (data.isDeposit) {
                DAI.transfer(msg.sender, availableToSpend - maxToSpend);
            } else {
                CHAI.transfer(msg.sender, availableToSpend - maxToSpend);
            }
        }
    }

    function performJoinAction(uint256 maxToSpend)
        internal
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        approveAddress(address(CHAI), address(DAI));
        CHAI.join(address(this), maxToSpend);
        amountSpentOnOrder = maxToSpend;
        amountReceivedFromOrder = CHAI.balanceOf(address(this));
        CHAI.transfer(msg.sender, amountReceivedFromOrder);
    }

    function performExitAction(uint256 maxToSpend)
        internal
        returns (uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder)
    {
        CHAI.exit(address(this), maxToSpend);
        amountSpentOnOrder = maxToSpend;
        amountReceivedFromOrder = DAI.balanceOf(address(this));
        DAI.transfer(msg.sender, amountReceivedFromOrder);
    }

    function getMaxToSpend(
        bool targetAmountIsSource,
        uint256 targetAmount,
        uint256 availableToSpend,
        uint256 maxOrderSpend
    ) internal returns (uint256 max) {
        max = availableToSpend;
        if (targetAmountIsSource) {
            max = Math.min(Math.min(max, targetAmount), maxOrderSpend);
        }
        return max;
    }

    function getReturnByJoin(uint256 wad) external returns (uint256) {
        uint256 chi = (now > POT.rho()) ? POT.drip() : POT.chi();
        return rdiv(wad, chi);
    }

    function getReturnByExit(uint256 wad) external returns (uint256) {
        uint256 chi = (now > POT.rho()) ? POT.drip() : POT.chi();
        return rmul(chi, wad);
    }

    uint256 constant RAY = 10**27;

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    function rmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        // always rounds down
        z = mul(x, y) / RAY;
    }

    function rdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        // always rounds down
        z = mul(x, RAY) / y;
    }
}
