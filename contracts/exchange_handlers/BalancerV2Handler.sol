pragma solidity 0.5.7;
pragma experimental ABIEncoderV2;

import "../lib/SafeMath.sol";
import "../lib/Math.sol";
import "../lib/Utils.sol";
import "../lib/AllowanceSetter.sol";
import "./ExchangeHandler.sol";
import "../lib/TotleControl.sol";

import "../lib/BalancerV2SwapLib.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


interface WETH {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface IVault{
    function swap(
        BalancerV2SwapLib.SingleSwap calldata singleSwap,
        BalancerV2SwapLib.FundManagement calldata funds,
        uint256 limit,
        uint256 deadline
    ) external payable returns (uint256);
}

interface BV2Pool {
    function getPoolId() external returns (bytes32 _poolId);
    function getVault() external returns (IVault _vault);
}


/// @title BalancerV2Handler
/// @notice Handles the all BalancerHandler trades for the primary contract
contract BalancerV2Handler is ExchangeHandler, AllowanceSetter {

    /*
     *   State Variables
     */
    WETH weth;
    /*
     *   Types
     */

    /// @notice Constructor
    constructor(address _weth) public {
        weth = WETH(_weth);
    }

    struct OrderData {
        address pool;
        address tokenIn;
        address tokenOut;
        uint256 maxOrderSpend;
    }

    event OrderPerformed(address caller, address pool, address tokenIn, address tokenOut, uint256 amountSpentOnOrder, uint256 amountReceivedFromOrder, uint256 timestamp);

    /*
     *   Public functions
     */

    /*
     *   Internal functions
     */

    function getMaxToSpend(
        uint256 targetAmount,
        uint256 availableToSpend,
        uint256 maxOrderSpend
    ) internal returns (uint256 max) {
        max = Math.min(Math.min(availableToSpend, targetAmount), maxOrderSpend);
        return max;
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
        IERC20(data.tokenIn).transferFrom(msg.sender, address(this), availableToSpend);

        amountSpentOnOrder = getMaxToSpend(
            targetAmount,
            availableToSpend,
            data.maxOrderSpend
        );
        
        if (data.tokenIn == address(weth)) {
            weth.deposit.value(amountSpentOnOrder)();
        }
        
        uint256 prevContractAmount;
        if (amountSpentOnOrder > 0) {            
            BV2Pool pool = BV2Pool(data.pool);           
            IVault vault = pool.getVault();

            approveAddress(address(vault), data.tokenIn);
            approveAddress(msg.sender, data.tokenOut);

            bytes32 poolId = pool.getPoolId();  
             
            BalancerV2SwapLib.SingleSwap memory singleSwap = BalancerV2SwapLib.SingleSwap(
                poolId,
                BalancerV2SwapLib.SwapKind.GIVEN_IN,
                IAsset(data.tokenIn),
                IAsset(data.tokenOut),
                amountSpentOnOrder,
                ""
            );

            BalancerV2SwapLib.FundManagement memory fundManagement = BalancerV2SwapLib.FundManagement(
                address(this),
                false,
                address(this),
                false
            );

            amountReceivedFromOrder = vault.swap(   // Getting amountCalculated
                singleSwap,
                fundManagement,
                0,
                block.timestamp
            );
            

        }
        
        if (amountSpentOnOrder < availableToSpend) {
            if (data.tokenIn == address(weth)) {
                msg.sender.transfer(availableToSpend - amountSpentOnOrder);
            } else {
                ERC20SafeTransfer.safeTransfer(
                    data.tokenIn,
                    msg.sender,
                    availableToSpend - amountSpentOnOrder
                );
            }
        }
        
        if (data.tokenOut == address(weth)) {
            weth.withdraw(amountReceivedFromOrder);
            msg.sender.transfer(amountReceivedFromOrder);
        } else {
            ERC20SafeTransfer.safeTransfer(
                data.tokenOut,
                msg.sender,
                amountReceivedFromOrder
            );
        }

        emit OrderPerformed(msg.sender, data.pool, data.tokenIn, data.tokenOut, amountSpentOnOrder, amountReceivedFromOrder, block.timestamp);

    }

    /*
     *   Payable fallback function
     */

    function() external payable {}
}