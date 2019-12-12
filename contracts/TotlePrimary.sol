pragma solidity 0.5.7;
pragma experimental ABIEncoderV2;

import "./lib/Withdrawable.sol";
import "./lib/Pausable.sol";
import "./lib/TokenTransferProxy.sol";
import "./lib/Utils.sol";
import "./lib/ERC20SafeTransfer.sol";
import "./lib/Partner.sol";
import "./lib/Math.sol";
import "./exchange_handlers/ExchangeHandler.sol";

/// @title The primary contract for Totle
contract TotlePrimary is Withdrawable, Pausable {

    /*
    *   State Variables
    */

    TokenTransferProxy public tokenTransferProxy;
    mapping(address => bool) public signers;
    /* Logger public logger; */

    /*
    *   Types
    */

    // Structs
    struct Order {
        address payable exchangeHandler;
        bytes encodedPayload;
    }

    struct Trade {
        address sourceToken;
        address destinationToken;
        uint256 amount;
        bool isSourceAmount; //true if amount is sourceToken, false if it's destinationToken
        Order[] orders;
    }

    struct Swap {
        Trade[] trades;
        uint256 minimumExchangeRate;
        uint256 minimumDestinationAmount;
        uint256 sourceAmount;
        uint256 tradeToTakeFeeFrom;
        bool takeFeeFromSource; //Takes the fee before the trade if true, takes it after if false
        address payable redirectAddress;
        bool required;
    }

    struct SwapCollection {
        Swap[] swaps;
        address payable partnerContract;
        uint256 expirationBlock;
        bytes32 id;
        uint256 maxGasPrice;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct TokenBalance {
        address tokenAddress;
        uint256 balance;
    }

    struct FeeVariables {
        uint256 feePercentage;
        Partner partner;
        uint256 totalFee;
    }

    struct AmountsSpentReceived{
        uint256 spent;
        uint256 received;
    }
    /*
    *   Events
    */

    event LogSwapCollection(
        bytes32 indexed id,
        address indexed partnerContract,
        address indexed user
    );

    event LogSwap(
        bytes32 indexed id,
        address sourceAsset,
        address destinationAsset,
        uint256 sourceAmount,
        uint256 destinationAmount,
        address feeAsset,
        uint256 feeAmount
    );

    /// @notice Constructor
    /// @param _tokenTransferProxy address of the TokenTransferProxy
    /// @param _signer the suggester's address that signs the payloads. More can be added with add/removeSigner functions
    constructor (address _tokenTransferProxy, address _signer/*, address _logger*/) public {
        tokenTransferProxy = TokenTransferProxy(_tokenTransferProxy);
        signers[_signer] = true;
        /* logger = Logger(_logger); */
    }

    /*
    *   Public functions
    */

    modifier notExpired(SwapCollection memory swaps) {
        require(swaps.expirationBlock > block.number, "Expired");
        _;
    }

    modifier validSignature(SwapCollection memory swaps){
        bytes32 hash = keccak256(abi.encode(swaps.swaps, swaps.partnerContract, swaps.expirationBlock, swaps.id, swaps.maxGasPrice, msg.sender));
        require(signers[ecrecover(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)), swaps.v, swaps.r, swaps.s)], "Invalid signature");
        _;
    }

    modifier notAboveMaxGas(SwapCollection memory swaps){
        require(tx.gasprice <= swaps.maxGasPrice, "Gas price too high");
        _;
    }

    /// @notice Performs the requested set of swaps
    /// @param swaps The struct that defines the collection of swaps to perform
    function performSwapCollection(
        SwapCollection memory swaps
    )
        public
        payable
        whenNotPaused
        notExpired(swaps)
        validSignature(swaps)
        notAboveMaxGas(swaps)
    {
        TokenBalance[20] memory balances;
        balances[0] = TokenBalance(address(Utils.eth_address()), msg.value);
        //this.log("Created eth balance", balances[0].balance, 0x0);
        for(uint256 swapIndex = 0; swapIndex < swaps.swaps.length; swapIndex++){
            //this.log("About to perform swap", swapIndex, swaps.id);
            performSwap(swaps.id, swaps.swaps[swapIndex], balances, swaps.partnerContract);
        }
        emit LogSwapCollection(swaps.id, swaps.partnerContract, msg.sender);
        transferAllTokensToUser(balances);
    }

    function addSigner(address newSigner) public onlyOwner {
         signers[newSigner] = true;
    }

    function removeSigner(address signer) public onlyOwner {
         signers[signer] = false;
    }

    /*
    *   Internal functions
    */


    function performSwap(
        bytes32 swapCollectionId,
        Swap memory swap,
        TokenBalance[20] memory balances,
        address payable partnerContract
    )
        internal
    {
        if(!transferFromSenderDifference(balances, swap.trades[0].sourceToken, swap.sourceAmount)){
            if(swap.required){
                revert("Failed to get tokens for swap");
            } else {
                return;
            }
        }
        uint256 amountSpentFirstTrade = 0;
        uint256 amountReceived = 0;
        uint256 feeAmount = 0;
        for(uint256 tradeIndex = 0; tradeIndex < swap.trades.length; tradeIndex++){
            if(tradeIndex == swap.tradeToTakeFeeFrom && swap.takeFeeFromSource){
                feeAmount = takeFee(balances, swap.trades[tradeIndex].sourceToken, partnerContract,tradeIndex==0 ? swap.sourceAmount : amountReceived);
            }
            uint256 tempSpent;
            //this.log("About to performTrade",0,0x0);
            (tempSpent, amountReceived) = performTrade(
                swap.trades[tradeIndex],
                balances,
                Utils.min(
                    tradeIndex == 0 ? swap.sourceAmount : amountReceived,
                    balances[findToken(balances, swap.trades[tradeIndex].sourceToken)].balance
                )
            );
            if(!swap.trades[tradeIndex].isSourceAmount && amountReceived < swap.trades[tradeIndex].amount){
                if(swap.required){
                    revert("Not enough destination amount");
                }
                return;
            }
            if(tradeIndex == 0){
                amountSpentFirstTrade = tempSpent;
                if(feeAmount != 0){
                    amountSpentFirstTrade += feeAmount;
                }
            }
            if(tradeIndex == swap.tradeToTakeFeeFrom && !swap.takeFeeFromSource){
                feeAmount = takeFee(balances, swap.trades[tradeIndex].destinationToken, partnerContract, amountReceived);
                amountReceived -= feeAmount;
            }
        }
        //this.log("About to emit LogSwap", 0, 0x0);
        emit LogSwap(
            swapCollectionId,
            swap.trades[0].sourceToken,
            swap.trades[swap.trades.length-1].destinationToken,
            amountSpentFirstTrade,
            amountReceived,
            swap.takeFeeFromSource?swap.trades[swap.tradeToTakeFeeFrom].sourceToken:swap.trades[swap.tradeToTakeFeeFrom].destinationToken,
            feeAmount
        );

        if(amountReceived < swap.minimumDestinationAmount){
            //this.log("Minimum destination amount failed", 0, 0x0);
            revert("Got less than minimumDestinationAmount");
        } else if (minimumRateFailed(swap.trades[0].sourceToken, swap.trades[swap.trades.length-1].destinationToken,swap.sourceAmount, amountReceived, swap.minimumExchangeRate)){
            //this.log("Minimum rate failed", 0, 0x0);
            revert("Minimum exchange rate not met");
        }
        if(swap.redirectAddress != msg.sender && swap.redirectAddress != address(0x0)){
            //this.log("About to redirect tokens", amountReceived, 0x0);
            uint256 destinationTokenIndex = findToken(balances,swap.trades[swap.trades.length-1].destinationToken);
            uint256 amountToSend = Math.min(amountReceived, balances[destinationTokenIndex].balance);
            transferTokens(balances, destinationTokenIndex, swap.redirectAddress, amountToSend);
            removeBalance(balances, swap.trades[swap.trades.length-1].destinationToken, amountToSend);
        }
    }

    function performTrade(
        Trade memory trade, 
        TokenBalance[20] memory balances,
        uint256 availableToSpend
    ) 
        internal returns (uint256 totalSpent, uint256 totalReceived)
    {
        uint256 tempSpent = 0;
        uint256 tempReceived = 0;
        for(uint256 orderIndex = 0; orderIndex < trade.orders.length; orderIndex++){
            if((availableToSpend - totalSpent) * 10000 < availableToSpend){
                break;
            } else if(!trade.isSourceAmount && tempReceived == trade.amount){
                break;
            } else if (trade.isSourceAmount && tempSpent == trade.amount){
                break;
            }
            //this.log("About to perform order", orderIndex,0x0);
            (tempSpent, tempReceived) = performOrder(
                trade.orders[orderIndex], 
                availableToSpend - totalSpent,
                trade.isSourceAmount ? availableToSpend - totalSpent : trade.amount - totalReceived, 
                trade.isSourceAmount,
                trade.sourceToken, 
                balances);
            //this.log("Order performed",0,0x0);
            totalSpent += tempSpent;
            totalReceived += tempReceived;
        }
        addBalance(balances, trade.destinationToken, totalReceived);
        removeBalance(balances, trade.sourceToken, totalSpent);
        //this.log("Trade performed",tempSpent, 0);
    }

    function performOrder(
        Order memory order, 
        uint256 availableToSpend,
        uint256 targetAmount,
        bool isSourceAmount,
        address tokenToSpend,
        TokenBalance[20] memory balances
    )
        internal returns (uint256 spent, uint256 received)
    {
        //this.log("Performing order", availableToSpend, 0x0);

        if(tokenToSpend == Utils.eth_address()){
            (spent, received) = ExchangeHandler(order.exchangeHandler).performOrder.value(availableToSpend)(order.encodedPayload, availableToSpend, targetAmount, isSourceAmount);

        } else {
            transferTokens(balances, findToken(balances, tokenToSpend), order.exchangeHandler, availableToSpend);
            (spent, received) = ExchangeHandler(order.exchangeHandler).performOrder(order.encodedPayload, availableToSpend, targetAmount, isSourceAmount);
        }
        //this.log("Performing order", spent,0x0);
        //this.log("Performing order", received,0x0);
    }

    function minimumRateFailed(
        address sourceToken,
        address destinationToken,
        uint256 sourceAmount,
        uint256 destinationAmount,
        uint256 minimumExchangeRate
    )
        internal returns(bool failed)
    {
        //this.log("About to get source decimals",sourceAmount,0x0);
        uint256 sourceDecimals = sourceToken == Utils.eth_address() ? 18 : Utils.getDecimals(sourceToken);
        //this.log("About to get destination decimals",destinationAmount,0x0);
        uint256 destinationDecimals = destinationToken == Utils.eth_address() ? 18 : Utils.getDecimals(destinationToken);
        //this.log("About to calculate amount got",0,0x0);
        uint256 rateGot = Utils.calcRateFromQty(sourceAmount, destinationAmount, sourceDecimals, destinationDecimals);
        //this.log("Minimum rate failed", rateGot, 0x0);
        return rateGot < minimumExchangeRate;
    }

    function takeFee(
        TokenBalance[20] memory balances,
        address token,
        address payable partnerContract,
        uint256 amountTraded
    )
        internal
        returns (uint256 feeAmount)
    {
        Partner partner = Partner(partnerContract);
        uint256 feePercentage = partner.getTotalFeePercentage();
        //this.log("Got fee percentage", feePercentage, 0x0);
        feeAmount = calculateFee(amountTraded, feePercentage);
        //this.log("Taking fee", feeAmount, 0);
        transferTokens(balances, findToken(balances, token), partnerContract, feeAmount);
        removeBalance(balances, findToken(balances, token), feeAmount);
        //this.log("Took fee", 0, 0x0);
        return feeAmount;
    }

    function transferFromSenderDifference(
        TokenBalance[20] memory balances,
        address token,
        uint256 sourceAmount
    )
        internal returns (bool)
    {
        if(token == Utils.eth_address()){
            if(sourceAmount>balances[0].balance){
                //this.log("Not enough eth", 0,0x0);
                return false;
            }
            //this.log("Enough eth", 0,0x0);
            return true;
        }

        uint256 tokenIndex = findToken(balances, token);
        if(sourceAmount>balances[tokenIndex].balance){
            //this.log("Transferring in token", 0,0x0);
            bool success;
            (success,) = address(tokenTransferProxy).call(abi.encodeWithSignature("transferFrom(address,address,address,uint256)", token, msg.sender, address(this), sourceAmount - balances[tokenIndex].balance));
            if(success){
                //this.log("Got enough token", 0,0x0);
                balances[tokenIndex].balance = sourceAmount;
                return true;
            }
            //this.log("Didn't get enough token", 0,0x0);
            return false;
        }
        return true;
    }

    function transferAllTokensToUser(
        TokenBalance[20] memory balances
    )
        internal
    {
        //this.log("About to transfer all tokens", 0, 0x0);
        for(uint256 balanceIndex = 0; balanceIndex < balances.length; balanceIndex++){
            if(balanceIndex != 0 && balances[balanceIndex].tokenAddress == address(0x0)){
                return;
            }
            //this.log("Transferring tokens", uint256(balances[balanceIndex].balance),0x0);
            transferTokens(balances, balanceIndex, msg.sender, balances[balanceIndex].balance);
        }
    }



    function transferTokens(
        TokenBalance[20] memory balances,
        uint256 tokenIndex,
        address payable destination,
        uint256 tokenAmount
    )
        internal
    {
        if(tokenAmount > 0){
            if(balances[tokenIndex].tokenAddress == Utils.eth_address()){
                destination.transfer(tokenAmount);
            } else {
                require(ERC20SafeTransfer.safeTransfer(balances[tokenIndex].tokenAddress, destination, tokenAmount),'Transfer failed');
            }
        }
    }

    function findToken(
        TokenBalance[20] memory balances,
        address token
    )
        internal pure returns (uint256)
    {
        for(uint256 index = 0; index < balances.length; index++){
            if(balances[index].tokenAddress == token){
                return index;
            } else if (index != 0 && balances[index].tokenAddress == address(0x0)){
                balances[index] = TokenBalance(token, 0);
                return index;
            }
        }
    }

    function addBalance(
        TokenBalance[20] memory balances,
        address tokenAddress,
        uint256 amountToAdd
    )
        internal
        pure
    {
        uint256 tokenIndex = findToken(balances, tokenAddress);
        addBalance(balances, tokenIndex, amountToAdd);
    }

    function addBalance(
        TokenBalance[20] memory balances,
        uint256 balanceIndex,
        uint256 amountToAdd
    )
        internal
        pure
    {
       balances[balanceIndex].balance += amountToAdd;
    }

    function removeBalance(
        TokenBalance[20] memory balances,
        address tokenAddress,
        uint256 amountToRemove
    )
        internal
        pure
    {
        uint256 tokenIndex = findToken(balances, tokenAddress);
        removeBalance(balances, tokenIndex, amountToRemove);
    }

    function removeBalance(
        TokenBalance[20] memory balances,
        uint256 balanceIndex,
        uint256 amountToRemove
    )
        internal
        pure
    {
        balances[balanceIndex].balance -= amountToRemove;
    }

    // @notice Calculates the fee amount given a fee percentage and amount
    // @param amount the amount to calculate the fee based on
    // @param fee the percentage, out of 1 eth (e.g. 0.01 ETH would be 1%)
    function calculateFee(uint256 amount, uint256 fee) internal pure returns (uint256){
        return SafeMath.div(SafeMath.mul(amount, fee), 1 ether);
    }

    /*
    *   Payable fallback function
    */

    /// @notice payable fallback to allow handler or exchange contracts to return ether
    /// @dev only accounts containing code (ie. contracts) can send ether to contract
    function() external payable whenNotPaused {
        // Check in here that the sender is a contract! (to stop accidents)
        uint256 size;
        address sender = msg.sender;
        assembly {
            size := extcodesize(sender)
        }
        if (size == 0) {
            revert("EOA cannot send ether to primary fallback");
        }
    }
    event Log(string a, uint256 b, bytes32 c);

    function log(string memory a, uint256 b, bytes32 c) public {
        emit Log(a,b,c);
    }
}