# Totle Smart Contracts
When designing Totle, our aim was to provide a simple interface to connect users with the liquidity available across several decentralized exchanges. A key requirement for us was to not compromise on security; all trades must be executed atomically on-chain through a single ethereum transaction.

In order to achieve this, our smart contract must receive some arbitrary data to be used as the payload for each DEX trade. In addition, the contract must also track the amounts spent and received, ensuring exchange rates are equal to or better than expected.

To allow for rapid expansion of the platform, we also need an easy way to add integration with new exchanges. After reviewing a range of different exchange architectures, we decided on a modular design which would allow for extensibility as required.

## 1. Contract Architecture
The diagram below is a visual description of the Totle contract architecture. See section 3 for links to our contracts on Etherscan.

![Totle Smart Contract Architecture](https://raw.githubusercontent.com/TotlePlatform/contracts/master/doc/diagram.png)

### 1.1 TotlePrimary
The `TotlePrimary` contract is the sole entry point for external transactions and is responsible for performing sanity checks on the payload, executing trades via the respective exchange handler, and keeping count of amounts given and received in order to enforce minimum exchange rate requirements.

### 1.2 TokenTransferProxy
Originally designed and published by the team at 0x, the `TokenTransferProxy` is responsible for transferring ownership of ERC20 tokens from the user to the `TotlePrimary` contract on execution of a sell order. The user is therefore required to set an allowance for the `TokenTransferProxy` prior to selling any tokens via Totle. The `TokenTransferProxy` maintains a record of addresses which have been authorized to transfer tokens on its behalf, the only address with this authorization is the `TotlePrimary` contract. In case of an upgrade to the primary contract, Totle are the only authorized party approve this change. As the platform matures we may implement a safeguarding mechanism such as a multi-sig or time-locked contract to control address authorization and welcome feedback on this from the community.

### 1.3 ExchangeHandler
Due to the differing requirements of executing trades at each DEX, we employ the use of separate `ExchangeHandler` contracts. An `ExchangeHandler` is responsible for all implementation specific logic required by each DEX. This could range from depositing funds prior to initiating a trade to wrapping or unwrapping ether as required. It is a key requirement that we keep DEX logic separate from the primary contract in order to allow for expansion of the platform.

### 1.4 Trade flow
When the user submits a series of trades to the `TotlePrimary` contract, a transaction is sent which invokes the `performSwapCollection` function. After an initial sanity check on the payload data, any tokens that the user wishes to sell are transferred to the primary contract via the `TokenTransferProxy`, followed by a check to ensure enough ether will be available to conduct all trades.


The payload is split into separate trades (e.g. swap ZRX for ETH, then swap ETH for BAT), each of which can be subsequently split into orders across integrated DEXs in order to gain the optimal price. The `TotlePrimary` loops through each token trade, sequentially executing all orders at their respective exchange handlers.

A count is kept of the amounts spent and acquired, and after each trade the primary contract performs a check to ensure that all orders were executed equal to or above the minimum exchange rate. Subsequent to the execution of all trades, any ether and tokens gained (as well as any leftover, if any) from swapping are sent to the user and execution is completed.

During the appropriate trade in a swap (defined by the payload), a fee is calculated based on the partner contract in the payload and sent to said contract. The fee is prioritized to be taken in ETH or stables if possible, if not then it is taken in the output asset of the swap.

## 2.  Future Directions
Our key focus for the development of our smart contract platform revolves around security, gas optimization, and extensibility.


## 3. Contract Addresses

Deployment of updated contracts hasn't occured yet