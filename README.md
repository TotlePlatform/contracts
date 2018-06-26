# Totle Smart Contracts
When designing Totle, our aim was to provide a simple interface to connect users with the liquidity available across several decentralized exchanges. A key requirement for us was to not compromise on security; all trades must be executed atomically on-chain through a single ethereum transaction.

In order to achieve this, our smart contract must receive some arbitrary data to be used as the payload for each DEX trade. In addition, the contract must also track the amounts spent and received, ensuring exchange rates are equal to or better than expected.

To allow for rapid expansion of the platform, we also need an easy way to add integration with new exchanges. After reviewing a range of different exchange architectures, we decided on a modular design which would allow for extensibility as required.

## 1. Contract Architecture
The diagram below is a visual description of the Totle contract architecture. Source code for all our contracts is freely available to read at both Etherscan and Github — https://github.com/TotlePlatform/contracts.


### 1.1 TotlePrimary
The `TotlePrimary` contract is the sole entry point for external transactions and is responsible for performing sanity checks on the payload, executing trades via the respective exchange handler, and keeping count of amounts given and received in order to enforce minimum exchange rate requirements.

### 1.2 TokenTransferProxy
Originally designed and published by the team at 0x, the `TokenTransferProxy` is responsible for transferring ownership of ERC20 tokens from the user to the `TotlePrimary` contract on execution of a sell order. The user is therefore required to set an allowance for the `TokenTransferProxy` prior to selling any tokens via Totle. The `TokenTransferProxy` maintains a record of addresses which have been authorized to transfer tokens on its behalf, the only address with this authorization is the `TotlePrimary` contract. In case of an upgrade to the primary contract, Totle are the only authorized party approve this change. As the platform matures we may implement a safeguarding mechanism such as a multi-sig or time-locked contract to control address authorization and welcome feedback on this from the community.

### 1.3 ExchangeHandler
Due to the differing requirements of executing trades at each DEX, we employ the use of separate `ExchangeHandler` contracts. An `ExchangeHandler` is responsible for all implementation specific logic required by each DEX. This could range from depositing funds prior to initiating a trade to wrapping or unwrapping ether as required. It is a key requirement that we keep DEX logic separate from the primary contract in order to allow for expansion of the platform.

### 1.4 Trade flow
When the user submits a series of trades to the `TotlePrimary` contract, a transaction is sent which invokes the `executeOrders` function. After an initial sanity check on the payload data, any tokens that the user wishes to sell are transferred to the primary contract via the `TokenTransferProxy`, followed by a check to ensure enough ether will be available to conduct all trades.

The payload is split into separate trades (e.g. buy ZRX, sell OMG), each of which can be subsequently split into several DEX orders in order to gain the optimal price. The `TotlePrimary` loops through each token trade, sequentially executing all orders at their respective exchange handlers.

A count is kept of the amounts spent and acquired, and after each trade the primary contract performs a check to ensure that all orders were executed equal to or above the minimum exchange rate. Subsequent to the execution of all trades, any ether gained through tokens sales is returned to the user and execution is completed.

## 2.  Future Directions
Our key focus for the development of our smart contract platform revolves around extensibility, gas optimization and security. Security is paramount and whilst the contracts have currently undergone an internal audit, talks are in place for a full external audit prior to official launch.

Under the current payload design we are somewhat limited by what exchanges we are able to support for each DEX order. With the upcoming changes in version 0.5.0 of Solidity, we hope to utilize updates to the ABI encoder, allowing nesting of dynamic data types such as structs and arrays.