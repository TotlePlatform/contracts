## Issue A
Fixed, see lines [82-83] of `UniswapV2Handler.sol`

## Issue B

Fixed, see line [93] of `CompoundHandler.sol`

Note: There is no such validation available for CEther (no return value), but the functions used on CEther revert on errors regardless

## Issue C

ERC20SafeTransfer has been removed and the functionality replaced with OpenZeppelin's SafeERC20

## Issue D

Future deployments will include all `owner` addresses being multisigs

The exact implementation we will use isn't decided, but Gnosis Safe is a likely candidate

## Suggestion 1

The Solidity compiler version has been updated to 0.8.9

All warnings related to the version upgrade have been resolved

## Suggestion 2

NatSpec documentation has been expanded

Inline comments added in many places

## Suggestion 3

All TODOs have been resolved and removed

## Suggestion 4

BancorHandler has been updated to use the current suggested function on BancorNetwork, `convertByPath2`

## Suggestion 5

Tests have been updated to support current contract versions

Additional tests have been added and more will be added over time, as well as a generally increased focus on unit tests

## Suggestion 6

All relevant areas of code have been updated except for TotlePrimary:L288-L311 as the ability to redirect assets wants to be kept

## Suggestion 7 

The Gas token refund mechanism, and any references to it, has been removed

## Suggestion 8

SwapCollection.partnerContract was moved to above SwapCollection.v, combining the slots. `tokenCount` has also been added between them for suggestion 9. Swap.required was removed, all swaps are now "required".

## Suggestion 9

The parameter `SwapCollection.tokenCount`, determined by the backend and supplied in the payload, is now used to initialize the size of the TokenBalances array used to track balances

## Suggestion 10

The fields `minSourceAmount`/`maxSourceAmount` and references to them have been removed. Individual exchange handlers can have (and some do) the max source encoded if the need is relevant to have a max spend amount, but that is irrelevant to the notion of backup liquidity, which has been removed.

## Suggestion 11

The `chainId` field has been added to the signing and signature validation in order to protect against cross-chain replay of payloads

## Suggestion 12

The Checks-Effects pattern has been applied in these instances

## Suggestion 13

A `receive` function that allows only non-zero-length bytecode addresses (i.e. contracts with bytecode) has been added to ExchangeHandler, and similar fallback functions have been removed from individual handlers to avoid future confusion and to be sure that all handlers have this protection.

The `fallback` function has also been removed as there are no instended cases of eth being sent with data other than to the `performSwapCollection` function. The `fallback` is now only used in mocks for testing purposes.

## Suggestion 14

The extra call to `getAmountToGive` has been removed and the variable that was already initilized is now used instead

## Suggestion 15

The `staticExchangeChecks` function has been removed from both 0xv2 and 0xv3 handlers

## Suggestion 16

Extensive documentation will be written prior to further venues being added

## Suggestion 17

A reentrancy guard (OpenZeppelin implementation) has been added to the partner payout function and ETH transfers were changed from using `transfer` to `call`.

## Suggestion 18

Documentation has been updated to reflect current version. Address section has been wiped as current version isn't yet deployed on mainnet and no old contracts will be used.

## Suggestion 19

Off-chain portion will go through a rigorous security process prior to deployment
