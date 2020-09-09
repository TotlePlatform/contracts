pragma solidity 0.5.7;
pragma experimental ABIEncoderV2;

import "./lib/Withdrawable.sol";
import "./lib/Pausable.sol";
import "./lib/TokenTransferProxy.sol";
import "./lib/Utils.sol";
import "./lib/ERC20SafeTransfer.sol";
import "./lib/Partner.sol";
import "./lib/Math.sol";
import "./lib/TokenBalanceLibrary.sol";
import "./exchange_handlers/ExchangeHandler.sol";


interface IGST2 {
    function freeUpTo(uint256) external returns (uint256);
}


/// @title The primary contract for Totle
contract TotlePrimary is Withdrawable, Pausable {
    /*
     *   State Variables
     */

    IGST2 public constant GAS_TOKEN = IGST2(
        0x0000000000b3F879cb30FE243b4Dfee438691c04
    );
    TokenTransferProxy public tokenTransferProxy;
    mapping(address => bool) public signers;
    uint256 public MIN_REFUND_GAS_PRICE = 20000000000;
    /*
     *   Types
     */

    // Structs
    struct Order {
        address payable exchangeHandler;
        bytes encodedPayload;
        uint256 minSourceAmount;
        uint256 maxSourceAmount;
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
    constructor(address _tokenTransferProxy, address _signer) public {
        tokenTransferProxy = TokenTransferProxy(_tokenTransferProxy);
        signers[_signer] = true;
    }

    /*
     *   Public functions
     */

    modifier notExpired(SwapCollection memory swaps) {
        require(swaps.expirationBlock > block.number, "Expired");
        _;
    }

    modifier validSignature(SwapCollection memory swaps) {
        bytes32 hash = keccak256(
            abi.encode(
                swaps.swaps,
                swaps.partnerContract,
                swaps.expirationBlock,
                swaps.id,
                swaps.maxGasPrice,
                msg.sender
            )
        );
        require(
            signers[ecrecover(
                keccak256(
                    abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)
                ),
                swaps.v,
                swaps.r,
                swaps.s
            )],
            "Invalid signature"
        );
        _;
    }

    modifier notAboveMaxGas(SwapCollection memory swaps) {
        require(tx.gasprice <= swaps.maxGasPrice, "Gas price too high");
        _;
    }

    /// @notice Performs the requested set of swaps
    /// @param swaps The struct that defines the collection of swaps to perform
    function performSwapCollection(SwapCollection memory swaps)
        public
        payable
        whenNotPaused
        notExpired(swaps)
        validSignature(swaps)
        notAboveMaxGas(swaps)
    {
        uint256 startingGas = 0;
        if (tx.gasprice >= MIN_REFUND_GAS_PRICE) {
            startingGas = gasleft();
        }


        TokenBalanceLibrary.TokenBalance[20] memory balances;
        balances[0] = TokenBalanceLibrary.TokenBalance(
            address(Utils.eth_address()),
            msg.value
        );
        for (
            uint256 swapIndex = 0;
            swapIndex < swaps.swaps.length;
            swapIndex++
        ) {
            performSwap(
                swaps.id,
                swaps.swaps[swapIndex],
                balances,
                swaps.partnerContract
            );
        }
        emit LogSwapCollection(swaps.id, swaps.partnerContract, msg.sender);
        transferAllTokensToUser(balances);
        if (startingGas > 0) {
            refundGas(startingGas);
        }
    }

    function refundGas(uint256 startingGas) internal {
        uint256 gasRemaining = gasleft();
        uint256 gasSpent = startingGas - gasRemaining;
        uint256 tokensToFree = Math.min(
            (gasSpent + 14154) / 41130,
            (gasRemaining - 27710) / (1148 + 5722 + 150)
        );
        GAS_TOKEN.freeUpTo(tokensToFree);
    }

    function addSigner(address newSigner) public onlyOwner {
        signers[newSigner] = true;
    }

    function removeSigner(address signer) public onlyOwner {
        signers[signer] = false;
    }

    function updateMinRefundGasPrice(uint256 newMinRefundGasPrice)
        external
        onlyOwner
    {
        MIN_REFUND_GAS_PRICE = newMinRefundGasPrice;
    }

    /*
     *   Internal functions
     */

    function performSwap(
        bytes32 swapCollectionId,
        Swap memory swap,
        TokenBalanceLibrary.TokenBalance[20] memory balances,
        address payable partnerContract
    ) internal {
        if (
            !transferFromSenderDifference(
                balances,
                swap.trades[0].sourceToken,
                swap.sourceAmount
            )
        ) {
            if (swap.required) {
                revert("Failed to get tokens for swap");
            } else {
                return;
            }
        }
        uint256 amountSpentFirstTrade = 0;
        uint256 amountReceived = 0;
        uint256 feeAmount = 0;
        for (
            uint256 tradeIndex = 0;
            tradeIndex < swap.trades.length;
            tradeIndex++
        ) {
            if (
                tradeIndex == swap.tradeToTakeFeeFrom && swap.takeFeeFromSource
            ) {
                feeAmount = takeFee(
                    balances,
                    swap.trades[tradeIndex].sourceToken,
                    partnerContract,
                    tradeIndex == 0 ? swap.sourceAmount : amountReceived
                );
            }
            uint256 tempSpent;
            (tempSpent, amountReceived) = performTrade(
                swap.trades[tradeIndex],
                balances,
                Utils.min(
                    tradeIndex == 0 ? swap.sourceAmount : amountReceived,
                    balances[TokenBalanceLibrary.findToken(
                        balances,
                        swap.trades[tradeIndex].sourceToken
                    )]
                        .balance
                )
            );
            if (
                !swap.trades[tradeIndex].isSourceAmount &&
                amountReceived < swap.trades[tradeIndex].amount
            ) {
                if (swap.required) {
                    revert("Not enough destination amount");
                }
                return;
            }
            if (tradeIndex == 0) {
                amountSpentFirstTrade = tempSpent;
                if (feeAmount != 0) {
                    amountSpentFirstTrade += feeAmount;
                }
            }
            if (
                tradeIndex == swap.tradeToTakeFeeFrom && !swap.takeFeeFromSource
            ) {
                feeAmount = takeFee(
                    balances,
                    swap.trades[tradeIndex].destinationToken,
                    partnerContract,
                    amountReceived
                );
                amountReceived -= feeAmount;
            }
        }
        emit LogSwap(
            swapCollectionId,
            swap.trades[0].sourceToken,
            swap.trades[swap.trades.length - 1].destinationToken,
            amountSpentFirstTrade,
            amountReceived,
            swap.takeFeeFromSource
                ? swap.trades[swap.tradeToTakeFeeFrom].sourceToken
                : swap.trades[swap.tradeToTakeFeeFrom].destinationToken,
            feeAmount
        );

        if (amountReceived < swap.minimumDestinationAmount) {
            revert("Got less than minimumDestinationAmount");
        } else if (
            minimumRateFailed(
                swap.trades[0].sourceToken,
                swap.trades[swap.trades.length - 1].destinationToken,
                swap.sourceAmount,
                amountReceived,
                swap.minimumExchangeRate
            )
        ) {
            revert("Minimum exchange rate not met");
        }
        if (
            swap.redirectAddress != msg.sender &&
            swap.redirectAddress != address(0x0)
        ) {
            uint256 destinationTokenIndex = TokenBalanceLibrary.findToken(
                balances,
                swap.trades[swap.trades.length - 1].destinationToken
            );
            uint256 amountToSend = Math.min(
                amountReceived,
                balances[destinationTokenIndex].balance
            );
            transferTokens(
                balances,
                destinationTokenIndex,
                swap.redirectAddress,
                amountToSend
            );
            TokenBalanceLibrary.removeBalance(
                balances,
                swap.trades[swap.trades.length - 1].destinationToken,
                amountToSend
            );
        }
    }

    function performTrade(
        Trade memory trade,
        TokenBalanceLibrary.TokenBalance[20] memory balances,
        uint256 availableToSpend
    ) internal returns (uint256 totalSpent, uint256 totalReceived) {
        uint256 tempSpent = 0;
        uint256 tempReceived = 0;
        uint256 missingSpend = 0; // This is the amount that we expected to have spent, but didn't. Not to be confused with the total amount left to spend
        uint256 totalRemainingExcess = getTotalExcess(trade);
        for (
            uint256 orderIndex = 0;
            orderIndex < trade.orders.length;
            orderIndex++
        ) {
            if ((availableToSpend - totalSpent) * 10000 < availableToSpend) {
                break;
            } else if (trade.isSourceAmount && tempSpent == trade.amount) {
                break;
            }
            uint256 targetSpend = getTargetSpend(
                trade.orders[orderIndex].minSourceAmount,
                trade.orders[orderIndex].maxSourceAmount,
                totalRemainingExcess,
                missingSpend);
            (tempSpent, tempReceived) = performOrder(
                trade.orders[orderIndex],
                availableToSpend - totalSpent,
                trade.isSourceAmount,
                trade.sourceToken,
                balances
            );
            totalRemainingExcess -= (trade.orders[orderIndex].maxSourceAmount -
                trade.orders[orderIndex].minSourceAmount);
            if (tempSpent < trade.orders[orderIndex].minSourceAmount) {
                missingSpend += (targetSpend - tempSpent);
            }
            totalSpent += tempSpent;
            totalReceived += tempReceived;
        }
        TokenBalanceLibrary.addBalance(
            balances,
            trade.destinationToken,
            totalReceived
        );
        TokenBalanceLibrary.removeBalance(
            balances,
            trade.sourceToken,
            totalSpent
        );
    }

    function performOrder(
        Order memory order,
        uint256 targetAmount,
        bool isSourceAmount,
        address tokenToSpend,
        TokenBalanceLibrary.TokenBalance[20] memory balances
    ) internal returns (uint256 spent, uint256 received) {
        if (tokenToSpend == Utils.eth_address()) {
            (spent, received) = ExchangeHandler(order.exchangeHandler)
                .performOrder
                .value(targetAmount)(
                order.encodedPayload,
                targetAmount,
                targetAmount,
                isSourceAmount
            );
        } else {
            transferTokens(
                balances,
                TokenBalanceLibrary.findToken(balances, tokenToSpend),
                order.exchangeHandler,
                targetAmount
            );
            (spent, received) = ExchangeHandler(order.exchangeHandler)
                .performOrder(
                order.encodedPayload,
                targetAmount,
                targetAmount,
                isSourceAmount
            );
        }
    }

    function getTargetSpend(
        uint256 minOrderAmount,
        uint256 maxOrderAmount,
        uint256 totalRemainingExcess,
        uint256 missingSpend
    ) internal returns (uint256 targetSpend) {
        if (missingSpend == 0 || minOrderAmount == maxOrderAmount) {
            return minOrderAmount;
        } else {
            return
                ((maxOrderAmount - minOrderAmount) * missingSpend) /
                totalRemainingExcess;
        }
    }

    function getTotalExcess(Trade memory trade)
        internal
        returns (uint256 totalExcess)
    {
        for (uint8 index = 0; index < trade.orders.length; index++) {
            totalExcess +=
                trade.orders[index].maxSourceAmount -
                trade.orders[index].minSourceAmount;
        }
        return totalExcess;
    }

    function minimumRateFailed(
        address sourceToken,
        address destinationToken,
        uint256 sourceAmount,
        uint256 destinationAmount,
        uint256 minimumExchangeRate
    ) internal returns (bool failed) {
        uint256 sourceDecimals = sourceToken == Utils.eth_address()
            ? 18
            : Utils.getDecimals(sourceToken);
        uint256 destinationDecimals = destinationToken == Utils.eth_address()
            ? 18
            : Utils.getDecimals(destinationToken);
        uint256 rateGot = Utils.calcRateFromQty(
            sourceAmount,
            destinationAmount,
            sourceDecimals,
            destinationDecimals
        );
        return rateGot < minimumExchangeRate;
    }

    function takeFee(
        TokenBalanceLibrary.TokenBalance[20] memory balances,
        address token,
        address payable partnerContract,
        uint256 amountTraded
    ) internal returns (uint256 feeAmount) {
        Partner partner = Partner(partnerContract);
        uint256 feePercentage = partner.getTotalFeePercentage();
        feeAmount = calculateFee(amountTraded, feePercentage);
        transferTokens(
            balances,
            TokenBalanceLibrary.findToken(balances, token),
            partnerContract,
            feeAmount
        );
        TokenBalanceLibrary.removeBalance(
            balances,
            TokenBalanceLibrary.findToken(balances, token),
            feeAmount
        );
        return feeAmount;
    }

    function transferFromSenderDifference(
        TokenBalanceLibrary.TokenBalance[20] memory balances,
        address token,
        uint256 sourceAmount
    ) internal returns (bool) {
        if (token == Utils.eth_address()) {
            if (sourceAmount > balances[0].balance) {
                return false;
            }
            return true;
        }

        uint256 tokenIndex = TokenBalanceLibrary.findToken(balances, token);
        if (sourceAmount > balances[tokenIndex].balance) {
            bool success;
            (success, ) = address(tokenTransferProxy).call(
                abi.encodeWithSignature(
                    "transferFrom(address,address,address,uint256)",
                    token,
                    msg.sender,
                    address(this),
                    sourceAmount - balances[tokenIndex].balance
                )
            );
            if (success) {
                balances[tokenIndex].balance = sourceAmount;
                return true;
            }
            return false;
        }
        return true;
    }

    function transferAllTokensToUser(
        TokenBalanceLibrary.TokenBalance[20] memory balances
    ) internal {
        for (
            uint256 balanceIndex = 0;
            balanceIndex < balances.length;
            balanceIndex++
        ) {
            if (
                balanceIndex != 0 &&
                balances[balanceIndex].tokenAddress == address(0x0)
            ) {
                return;
            }
            transferTokens(
                balances,
                balanceIndex,
                msg.sender,
                balances[balanceIndex].balance
            );
        }
    }

    function transferTokens(
        TokenBalanceLibrary.TokenBalance[20] memory balances,
        uint256 tokenIndex,
        address payable destination,
        uint256 tokenAmount
    ) internal {
        if (tokenAmount > 0) {
            if (balances[tokenIndex].tokenAddress == Utils.eth_address()) {
                destination.transfer(tokenAmount);
            } else {
                require(
                    ERC20SafeTransfer.safeTransfer(
                        balances[tokenIndex].tokenAddress,
                        destination,
                        tokenAmount
                    ),
                    "Transfer failed"
                );
            }
        }
    }

    // @notice Calculates the fee amount given a fee percentage and amount
    // @param amount the amount to calculate the fee based on
    // @param fee the percentage, out of 1 eth (e.g. 0.01 ETH would be 1%)
    function calculateFee(uint256 amount, uint256 fee)
        internal
        pure
        returns (uint256)
    {
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
}
