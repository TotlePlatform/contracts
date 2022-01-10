const UniswapHandler = artifacts.require("UniswapHandler")
const UniswapMock = artifacts.require("UniswapMock")
const StandardToken = artifacts.require("StandardToken")
const { default: Web3 } = require("web3")
const AbiEncoder = require("web3-eth-abi")
const ProxyTransferTester = artifacts.require("ProxyTransferTester")

contract('UniswapHandler', (accounts) => {
    var token,
        uniswapMock,
        uniswapHandler,
        proxyTransferTester

    beforeEach(async () => {
        proxyTransferTester = await ProxyTransferTester.new()
        token = await StandardToken.new(accounts[0], accounts[1])
        uniswapMock = await UniswapMock.new(token.address)
        uniswapHandler = await UniswapHandler.new(uniswapMock.address)
        await uniswapMock.depositEth({ value: 20000000000, from: accounts[1], gasPrice: 0 })
        await token.transfer(uniswapMock.address, 10000000000, { from: accounts[1], gasPrice: 0 })
        await proxyTransferTester.transferETH("0x0000000000000000000000000000000000000000", { value: (await web3.eth.getBalance(accounts[2])).toString(), from: accounts[2], gasPrice: 0 })
    })

    it("test performOrder() - eth -> token", async () => {
        const encodedPayload = AbiEncoder.encodeParameters(
            [
                {
                    "internalType": "address",
                    "name": "source",
                    "type": "address"
                },
                {
                    "internalType": "address",
                    "name": "destination",
                    "type": "address"
                },
                {
                    "internalType": "uint256",
                    "name": "amount",
                    "type": "uint256"
                }
            ]
            , ["0x0000000000000000000000000000000000000000", token.address, 50000]
        )
        await proxyTransferTester.transferETH(uniswapHandler.address, { value: 50000, gasPrice: 0 })
        await proxyTransferTester.transferETH(accounts[2], { value: 50000, gasPrice: 0 })
        const result = await uniswapHandler.performOrder.call(encodedPayload, 50000, 50000, { from: accounts[2], gasPrice: 0 });
        assert.equal(result.amountSpentOnOrder.toString(), "50000")
        assert.equal(result.amountReceivedFromOrder.toString(), "24924")
        await uniswapHandler.performOrder(encodedPayload, 50000, 50000, { from: accounts[2], gasPrice: 0 });
        assert.equal((await token.balanceOf(accounts[2])).toString(), 24924)
    })


    it("test performOrder() - token -> eth", async () => {
        const encodedPayload = AbiEncoder.encodeParameters(
            [
                {
                    "internalType": "address",
                    "name": "source",
                    "type": "address"
                },
                {
                    "internalType": "address",
                    "name": "destination",
                    "type": "address"
                },
                {
                    "internalType": "uint256",
                    "name": "amount",
                    "type": "uint256"
                }
            ]
            , [token.address, "0x0000000000000000000000000000000000000000", 50000]
        )
        await token.transfer(uniswapHandler.address, 50000, { gasPrice: 0 })
        const result = await uniswapHandler.performOrder.call(encodedPayload, 50000, 50000, { from: accounts[2], gasPrice: 0 });
        assert.equal(result.amountSpentOnOrder, 50000)
        assert.equal(result.amountReceivedFromOrder, 99699)
        await uniswapHandler.performOrder(encodedPayload, 50000, 50000, { from: accounts[2], gasPrice: 0 });
        assert.equal(await web3.eth.getBalance(accounts[2]), 99699)
    })

})
