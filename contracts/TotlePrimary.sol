pragma solidity 0.4.25;
pragma experimental ABIEncoderV2;

import "./lib/Withdrawable.sol";
import "./lib/TokenTransferProxy.sol";
import "./lib/Pausable.sol";
import "./lib/SafeMath.sol";
import "./lib/Utils.sol";
import "./lib/ErrorReporter.sol";
/* import "./lib/Logger.sol"; */
import "./lib/ERC20SafeTransfer.sol";
import "./lib/AffiliateRegistry.sol";
import "./exchange_handlers/ExchangeHandler.sol";

/// @title The primary contract for Totle
contract TotlePrimary is Withdrawable, Pausable {

    /*
    *   State Variables
    */

    mapping(address => bool) public handlerWhitelistMap;
    address[] public handlerWhitelistArray;
    AffiliateRegistry affiliateRegistry;
    address public defaultFeeAccount;

    TokenTransferProxy public tokenTransferProxy;
    ErrorReporter public errorReporter;
    /* Logger public logger; */

    /*
    *   Types
    */

    // Structs
    struct Trade {
        bool isSell;
        address tokenAddress;
        uint256 tokenAmount;
        bool optionalTrade;
        uint256 minimumExchangeRate;
        uint256 minimumAcceptableTokenAmount;
        Order[] orders;
    }

    struct Order {
        address exchangeHandler;
        bytes genericPayload;
    }

    struct TradeFlag {
        bool ignoreTrade;
        bool[] ignoreOrder;
    }

    struct CurrentAmounts {
        uint256 amountSpentOnTrade;
        uint256 amountReceivedFromTrade;
        uint256 amountLeftToSpendOnTrade;
    }

    /*
    *   Events
    */

    event LogRebalance(
        bytes32 id,
        uint256 totalEthTraded,
        uint256 totalFee
    );

    event LogTrade(
        bool isSell,
        address token,
        uint256 ethAmount,
        uint256 tokenAmount
    );

    /*
    *   Modifiers
    */

    modifier handlerWhitelisted(address handler) {
        if (!handlerWhitelistMap[handler]) {
            errorReporter.revertTx("Handler not in whitelist");
        }
        _;
    }

    modifier handlerNotWhitelisted(address handler) {
        if (handlerWhitelistMap[handler]) {
            errorReporter.revertTx("Handler already whitelisted");
        }
        _;
    }

    /// @notice Constructor
    /// @param _tokenTransferProxy address of the TokenTransferProxy
    /// @param _errorReporter the address of the error reporter contract
    constructor (address _tokenTransferProxy, address _affiliateRegistry, address _errorReporter, address _defaultFeeAccount/*, address _logger*/) public {
        /* require(_logger != address(0x0)); */
        tokenTransferProxy = TokenTransferProxy(_tokenTransferProxy);
        affiliateRegistry = AffiliateRegistry(_affiliateRegistry);
        errorReporter = ErrorReporter(_errorReporter);
        defaultFeeAccount = _defaultFeeAccount;
        /* logger = Logger(_logger); */
    }

    /*
    *   Public functions
    */

    /// @notice Update the default fee account
    /// @dev onlyOwner modifier only allows the contract owner to run the code
    /// @param newDefaultFeeAccount new default fee account
    function updateDefaultFeeAccount(address newDefaultFeeAccount) public onlyOwner {
        defaultFeeAccount = newDefaultFeeAccount;
    }

    /// @notice Add an exchangeHandler address to the whitelist
    /// @dev onlyOwner modifier only allows the contract owner to run the code
    /// @param handler Address of the exchange handler which permission needs adding
    function addHandlerToWhitelist(address handler)
        public
        onlyOwner
        handlerNotWhitelisted(handler)
    {
        handlerWhitelistMap[handler] = true;
        handlerWhitelistArray.push(handler);
    }

    /// @notice Remove an exchangeHandler address from the whitelist
    /// @dev onlyOwner modifier only allows the contract owner to run the code
    /// @param handler Address of the exchange handler which permission needs removing
    function removeHandlerFromWhitelist(address handler)
        public
        onlyOwner
        handlerWhitelisted(handler)
    {
        delete handlerWhitelistMap[handler];
        for (uint i = 0; i < handlerWhitelistArray.length; i++) {
            if (handlerWhitelistArray[i] == handler) {
                handlerWhitelistArray[i] = handlerWhitelistArray[handlerWhitelistArray.length - 1];
                handlerWhitelistArray.length -= 1;
                break;
            }
        }
    }

    /// @notice Performs the requested portfolio rebalance
    /// @param trades A dynamic array of trade structs
    function performRebalance(
        Trade[] memory trades,
        address feeAccount,
        bytes32 id
    )
        public
        payable
        whenNotPaused
    {
        if(!affiliateRegistry.isValidAffiliate(feeAccount)){
            feeAccount = defaultFeeAccount;
        }
        Affiliate affiliate = Affiliate(feeAccount);
        uint256 feePercentage = affiliate.getTotalFeePercentage();

        /* logger.log("Starting Rebalance..."); */

        TradeFlag[] memory tradeFlags = initialiseTradeFlags(trades);

        staticChecks(trades, tradeFlags);

        /* logger.log("Static checks passed."); */

        transferTokens(trades, tradeFlags);

        /* logger.log("Tokens transferred."); */

        uint256 etherBalance = msg.value;
        uint256 totalFee = 0;
        /* logger.log("Ether balance arg2: etherBalance.", etherBalance); */
        uint256 totalTraded = 0;
        for (uint256 i; i < trades.length; i++) {
            Trade memory thisTrade = trades[i];
            TradeFlag memory thisTradeFlag = tradeFlags[i];

            CurrentAmounts memory amounts = CurrentAmounts({
                amountSpentOnTrade: 0,
                amountReceivedFromTrade: 0,
                amountLeftToSpendOnTrade: thisTrade.isSell ? thisTrade.tokenAmount : calculateMaxEtherSpend(thisTrade, etherBalance, feePercentage)
            });
            /* logger.log("Going to perform trade. arg2: amountLeftToSpendOnTrade", amounts.amountLeftToSpendOnTrade); */

            performTrade(
                thisTrade,
                thisTradeFlag,
                amounts
            );
            emit LogTrade(thisTrade.isSell, thisTrade.tokenAddress, thisTrade.isSell ? amounts.amountReceivedFromTrade:amounts.amountSpentOnTrade, thisTrade.isSell?amounts.amountSpentOnTrade:amounts.amountReceivedFromTrade);

            uint256 ethTraded;
            uint256 ethFee;
            if(thisTrade.isSell){
                ethTraded = amounts.amountReceivedFromTrade;
            } else {
                ethTraded = amounts.amountSpentOnTrade;
            }
            totalTraded += ethTraded;
            ethFee = calculateFee(ethTraded, feePercentage);
            totalFee = SafeMath.add(totalFee, ethFee);
            /* logger.log("Finished performing trade arg2: amountReceivedFromTrade, arg3: amountSpentOnTrade.", amounts.amountReceivedFromTrade, amounts.amountSpentOnTrade); */

            if (amounts.amountReceivedFromTrade == 0 && thisTrade.optionalTrade) {
                /* logger.log("Received 0 from trade and this is an optional trade. Skipping."); */
                continue;
            }

            /* logger.log(
                "Going to check trade acceptable amounts arg2: amountSpentOnTrade, arg2: amountReceivedFromTrade.",
                amounts.amountSpentOnTrade,
                amounts.amountReceivedFromTrade
            ); */

            if (!checkIfTradeAmountsAcceptable(thisTrade, amounts.amountSpentOnTrade, amounts.amountReceivedFromTrade)) {
                errorReporter.revertTx("Amounts spent/received in trade not acceptable");
            }

            /* logger.log("Trade passed the acceptable amounts check."); */

            if (thisTrade.isSell) {
                /* logger.log(
                    "This is a sell trade, adding ether to our balance arg2: etherBalance, arg3: amountReceivedFromTrade",
                    etherBalance,
                    amounts.amountReceivedFromTrade
                ); */
                etherBalance = SafeMath.sub(SafeMath.add(etherBalance, ethTraded), ethFee);
            } else {
                /* logger.log(
                    "This is a buy trade, deducting ether from our balance arg2: etherBalance, arg3: amountSpentOnTrade",
                    etherBalance,
                    amounts.amountSpentOnTrade
                ); */
                etherBalance = SafeMath.sub(SafeMath.sub(etherBalance, ethTraded), ethFee);
            }

            /* logger.log("Transferring tokens to the user arg:6 tokenAddress.", 0,0,0,0, thisTrade.tokenAddress); */

            transferTokensToUser(
                thisTrade.tokenAddress,
                thisTrade.isSell ? amounts.amountLeftToSpendOnTrade : amounts.amountReceivedFromTrade
            );

        }
        emit LogRebalance(id, totalTraded, totalFee);
        if(totalFee > 0){
            feeAccount.transfer(totalFee);
        }
        if(etherBalance > 0) {
            /* logger.log("Got a positive ether balance, sending to the user arg2: etherBalance.", etherBalance); */
            msg.sender.transfer(etherBalance);
        }
    }

    /// @notice Performs static checks on the rebalance payload before execution
    /// @dev This function is public so a rebalance can be checked before performing a rebalance
    /// @param trades A dynamic array of trade structs
    /// @param tradeFlags A dynamic array of flags indicating trade and order status
    function staticChecks(
        Trade[] trades,
        TradeFlag[] tradeFlags
    )
        public
        view
        whenNotPaused
    {
        bool previousBuyOccured = false;

        for (uint256 i; i < trades.length; i++) {
            Trade memory thisTrade = trades[i];
            if (thisTrade.isSell) {
                if (previousBuyOccured) {
                    errorReporter.revertTx("A buy has occured before this sell");
                }

                if (!Utils.tokenAllowanceAndBalanceSet(msg.sender, thisTrade.tokenAddress, thisTrade.tokenAmount, address(tokenTransferProxy))) {
                    if (!thisTrade.optionalTrade) {
                        errorReporter.revertTx("Taker has not sent allowance/balance on a non-optional trade");
                    }
                    /* logger.log(
                        "Attempt to sell a token without allowance or sufficient balance arg2: tokenAmount, arg6: tokenAddress . Otional trade, ignoring.",
                        thisTrade.tokenAmount,
                        0,
                        0,
                        0,
                        thisTrade.tokenAddress
                    ); */
                    tradeFlags[i].ignoreTrade = true;
                    continue;
                }
            } else {
                previousBuyOccured = true;
            }

            /* logger.log("Checking that all the handlers are whitelisted."); */
            for (uint256 j; j < thisTrade.orders.length; j++) {
                Order memory thisOrder = thisTrade.orders[j];
                if ( !handlerWhitelistMap[thisOrder.exchangeHandler] ) {
                    /* logger.log(
                        "Trying to use a handler that is not whitelisted arg6: exchangeHandler.",
                        0,
                        0,
                        0,
                        0,
                        thisOrder.exchangeHandler
                    ); */
                    tradeFlags[i].ignoreOrder[j] = true;
                    continue;
                }
            }
        }
    }

    /*
    *   Internal functions
    */

    /// @notice Initialises the trade flag struct
    /// @param trades the trades used to initialise the flags
    /// @return tradeFlags the initialised flags
    function initialiseTradeFlags(Trade[] trades)
        internal
        returns (TradeFlag[])
    {
        /* logger.log("Initializing trade flags."); */
        TradeFlag[] memory tradeFlags = new TradeFlag[](trades.length);
        for (uint256 i = 0; i < trades.length; i++) {
            tradeFlags[i].ignoreOrder = new bool[](trades[i].orders.length);
        }
        return tradeFlags;
    }

    /// @notice Transfers the given amount of tokens back to the msg.sender
    /// @param tokenAddress the address of the token to transfer
    /// @param tokenAmount the amount of tokens to transfer
    function transferTokensToUser(
        address tokenAddress,
        uint256 tokenAmount
    )
        internal
    {
        /* logger.log("Transfering tokens to the user arg2: tokenAmount, arg6: .tokenAddress", tokenAmount, 0, 0, 0, tokenAddress); */
        if (tokenAmount > 0) {
            if (!ERC20SafeTransfer.safeTransfer(tokenAddress, msg.sender, tokenAmount)) {
                errorReporter.revertTx("Unable to transfer tokens to user");
            }
        }
    }

    /// @notice Executes the given trade
    /// @param trade a struct containing information about the trade
    /// @param tradeFlag a struct containing trade status information
    /// @param amounts a struct containing information about amounts spent
    /// and received in the rebalance
    function performTrade(
        Trade memory trade,
        TradeFlag memory tradeFlag,
        CurrentAmounts amounts
    )
        internal
    {
        /* logger.log("Performing trade"); */

        for (uint256 j; j < trade.orders.length; j++) {

            if(amounts.amountLeftToSpendOnTrade * 10000 < (amounts.amountSpentOnTrade + amounts.amountLeftToSpendOnTrade)){
                return;
            }

            if((trade.isSell ? amounts.amountSpentOnTrade : amounts.amountReceivedFromTrade) >= trade.tokenAmount ) {
                return;
            }

            if (tradeFlag.ignoreOrder[j] || amounts.amountLeftToSpendOnTrade == 0) {
                /* logger.log(
                    "Order ignore flag is set to true or have nothing left to spend arg2: amountLeftToSpendOnTrade",
                    amounts.amountLeftToSpendOnTrade
                ); */
                continue;
            }

            uint256 amountSpentOnOrder = 0;
            uint256 amountReceivedFromOrder = 0;

            Order memory thisOrder = trade.orders[j];

            /* logger.log("Setting order exchange handler arg6: exchangeHandler.", 0, 0, 0, 0, thisOrder.exchangeHandler); */
            ExchangeHandler thisHandler = ExchangeHandler(thisOrder.exchangeHandler);

            uint256 amountToGiveForOrder = Utils.min(
                thisHandler.getAmountToGive(thisOrder.genericPayload),
                amounts.amountLeftToSpendOnTrade
            );

            if (amountToGiveForOrder == 0) {
                /* logger.log(
                    "MASSIVE ERROR: amountToGiveForOrder was found to be 0, this hasn't been caught in preTradeChecks, which means dynamicExchangeChecks isnt written correctly!"
                ); */
                continue;
            }

            /* logger.log(
                "Calculating amountToGiveForOrder arg2: amountToGiveForOrder, arg3: amountLeftToSpendOnTrade.",
                amountToGiveForOrder,
                amounts.amountLeftToSpendOnTrade
            ); */

            if( !thisHandler.staticExchangeChecks(thisOrder.genericPayload) ) {
                /* logger.log("Order did not pass checks, skipping."); */
                continue;
            }

            if (trade.isSell) {
                /* logger.log("This is a sell.."); */
                if (!ERC20SafeTransfer.safeTransfer(trade.tokenAddress,address(thisHandler), amountToGiveForOrder)) {
                    if( !trade.optionalTrade ) errorReporter.revertTx("Unable to transfer tokens to handler");
                    else {
                        /* logger.log("Unable to transfer tokens to handler but the trade is optional"); */
                        return;
                    }
                }

                /* logger.log("Going to perform a sell order."); */
                (amountSpentOnOrder, amountReceivedFromOrder) = thisHandler.performSellOrder(thisOrder.genericPayload, amountToGiveForOrder);
                /* logger.log("Sell order performed arg2: amountSpentOnOrder, arg3: amountReceivedFromOrder", amountSpentOnOrder, amountReceivedFromOrder); */
            } else {
                /* logger.log("Going to perform a buy order."); */
                (amountSpentOnOrder, amountReceivedFromOrder) = thisHandler.performBuyOrder.value(amountToGiveForOrder)(thisOrder.genericPayload, amountToGiveForOrder);
                /* logger.log("Buy order performed arg2: amountSpentOnOrder, arg3: amountReceivedFromOrder", amountSpentOnOrder, amountReceivedFromOrder); */
            }


            if (amountReceivedFromOrder > 0) {
                amounts.amountLeftToSpendOnTrade = SafeMath.sub(amounts.amountLeftToSpendOnTrade, amountSpentOnOrder);
                amounts.amountSpentOnTrade = SafeMath.add(amounts.amountSpentOnTrade, amountSpentOnOrder);
                amounts.amountReceivedFromTrade = SafeMath.add(amounts.amountReceivedFromTrade, amountReceivedFromOrder);

                /* logger.log(
                    "Updated amounts arg2: amountLeftToSpendOnTrade, arg3: amountSpentOnTrade, arg4: amountReceivedFromTrade.",
                    amounts.amountLeftToSpendOnTrade,
                    amounts.amountSpentOnTrade,
                    amounts.amountReceivedFromTrade
                ); */
            }
        }

    }

    /// @notice Check if the amounts spent and gained on a trade are within the
    /// user"s set limits
    /// @param trade contains information on the given trade
    /// @param amountSpentOnTrade the amount that was spent on the trade
    /// @param amountReceivedFromTrade the amount that was received from the trade
    /// @return bool whether the trade passes the checks
    function checkIfTradeAmountsAcceptable(
        Trade trade,
        uint256 amountSpentOnTrade,
        uint256 amountReceivedFromTrade
    )
        internal
        view
        returns (bool passed)
    {
        /* logger.log("Checking if trade amounts are acceptable."); */
        uint256 tokenAmount = trade.isSell ? amountSpentOnTrade : amountReceivedFromTrade;
        passed = tokenAmount >= trade.minimumAcceptableTokenAmount;

        /*if( !passed ) {
             logger.log(
                "Received less than minimum acceptable tokens arg2: tokenAmount , arg3: minimumAcceptableTokenAmount.",
                tokenAmount,
                trade.minimumAcceptableTokenAmount
            );
        }*/

        if (passed) {
            uint256 tokenDecimals = Utils.getDecimals(ERC20(trade.tokenAddress));
            uint256 srcDecimals = trade.isSell ? tokenDecimals : Utils.eth_decimals();
            uint256 destDecimals = trade.isSell ? Utils.eth_decimals() : tokenDecimals;
            uint256 actualRate = Utils.calcRateFromQty(amountSpentOnTrade, amountReceivedFromTrade, srcDecimals, destDecimals);
            passed = actualRate >= trade.minimumExchangeRate;
        }

        /*if( !passed ) {
             logger.log(
                "Order rate was lower than minimum acceptable,  rate arg2: actualRate, arg3: minimumExchangeRate.",
                actualRate,
                trade.minimumExchangeRate
            );
        }*/
    }

    /// @notice Iterates through a list of token orders, transfer the SELL orders to this contract & calculates if we have the ether needed
    /// @param trades A dynamic array of trade structs
    /// @param tradeFlags A dynamic array of flags indicating trade and order status
    function transferTokens(Trade[] trades, TradeFlag[] tradeFlags) internal {
        for (uint256 i = 0; i < trades.length; i++) {
            if (trades[i].isSell && !tradeFlags[i].ignoreTrade) {

                /* logger.log(
                    "Transfering tokens arg2: tokenAmount, arg5: tokenAddress.",
                    trades[i].tokenAmount,
                    0,
                    0,
                    0,
                    trades[i].tokenAddress
                ); */
                if (
                    !tokenTransferProxy.transferFrom(
                        trades[i].tokenAddress,
                        msg.sender,
                        address(this),
                        trades[i].tokenAmount
                    )
                ) {
                    errorReporter.revertTx("TTP unable to transfer tokens to primary");
                }
           }
        }
    }

    /// @notice Calculates the maximum amount that should be spent on a given buy trade
    /// @param trade the buy trade to return the spend amount for
    /// @param etherBalance the amount of ether that we currently have to spend
    /// @return uint256 the maximum amount of ether we should spend on this trade
    function calculateMaxEtherSpend(Trade trade, uint256 etherBalance, uint256 feePercentage) internal view returns (uint256) {
        /// @dev This function should never be called for a sell
        assert(!trade.isSell);

        uint256 tokenDecimals = Utils.getDecimals(ERC20(trade.tokenAddress));
        uint256 srcDecimals = trade.isSell ? tokenDecimals : Utils.eth_decimals();
        uint256 destDecimals = trade.isSell ? Utils.eth_decimals() : tokenDecimals;
        uint256 maxSpendAtMinRate = Utils.calcSrcQty(trade.tokenAmount, srcDecimals, destDecimals, trade.minimumExchangeRate);

        return Utils.min(removeFee(etherBalance, feePercentage), maxSpendAtMinRate);
    }

    // @notice Calculates the fee amount given a fee percentage and amount
    // @param amount the amount to calculate the fee based on
    // @param fee the percentage, out of 1 eth (e.g. 0.01 ETH would be 1%)
    function calculateFee(uint256 amount, uint256 fee) internal view returns (uint256){
        return SafeMath.div(SafeMath.mul(amount, fee), 1 ether);
    }

    // @notice Calculates the cost if amount=cost+fee
    // @param amount the amount to calculate the base on
    // @param fee the percentage, out of 1 eth (e.g. 0.01 ETH would be 1%)
    function removeFee(uint256 amount, uint256 fee) internal view returns (uint256){
        return SafeMath.div(SafeMath.mul(amount, 1 ether), SafeMath.add(fee, 1 ether));
    }
    /*
    *   Payable fallback function
    */

    /// @notice payable fallback to allow handler or exchange contracts to return ether
    /// @dev only accounts containing code (ie. contracts) can send ether to this contract
    function() public payable whenNotPaused {
        // Check in here that the sender is a contract! (to stop accidents)
        uint256 size;
        address sender = msg.sender;
        assembly {
            size := extcodesize(sender)
        }
        if (size == 0) {
            errorReporter.revertTx("EOA cannot send ether to primary fallback");
        }
    }
}
