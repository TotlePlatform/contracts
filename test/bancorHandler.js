const BancorHandler = artifacts.require("BancorHandler")
const BancorMock = artifacts.require("BancorMock")
const StandardToken = artifacts.require("StandardToken")
const AbiEncoder = require("web3-eth-abi")
const ProxyTransferTester = artifacts.require("ProxyTransferTester")

contract('BancorHandler', (accounts) => {
    var token,
        bancorMock,
        bancorHandler,
        proxyTransferTester

    beforeEach(async () => {
        proxyTransferTester = await ProxyTransferTester.new()
        token = await StandardToken.new(accounts[0], accounts[1])
        bancorMock = await BancorMock.new(token.address)
        bancorHandler = await BancorHandler.new(bancorMock.address)
        await proxyTransferTester.transferETH(accounts[0], { value: (await web3.eth.getBalance(accounts[2])).toString(), from: accounts[2], gasPrice: 0 })

        await token.transfer(bancorMock.address, 10000000000, { from: accounts[0], gasPrice: 0 })
        await proxyTransferTester.transferETH(bancorMock.address, { value: "100000000", from: accounts[0], gasPrice: 0 })
    })

    it("test performOrder() - eth -> token", async () => {
        const encodedPayload = AbiEncoder.encodeParameters(
            HANDLER_DATA_ABI,
            [bancorMock.address, ['0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE', token.address, '0x0000000000000000000000000000000000000000', '0x0000000000000000000000000000000000000000', '0x0000000000000000000000000000000000000000', '0x0000000000000000000000000000000000000000', '0x0000000000000000000000000000000000000000'], token.address, 50000]
        )
        await proxyTransferTester.transferETH(accounts[2], { value: 50000, gasPrice: 0 })
        const result = await bancorHandler.performOrder.call(encodedPayload, 50000, 50000, { value:50000, from: accounts[2], gasPrice: 0 });
        assert.equal(result.amountSpentOnOrder.toString(), "50000")
        assert.equal(result.amountReceivedFromOrder.toString(), "24975")
        await bancorHandler.performOrder(encodedPayload, 50000, 50000, { value: 50000, from: accounts[2], gasPrice: 0 });
        assert.equal((await token.balanceOf(accounts[2])).toString(), "24975")
    })


    it("test performOrder() - token -> eth", async () => {
        const encodedPayload = AbiEncoder.encodeParameters(
            HANDLER_DATA_ABI,

            [bancorMock.address, [token.address, '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE', '0x0000000000000000000000000000000000000000', '0x0000000000000000000000000000000000000000', '0x0000000000000000000000000000000000000000', '0x0000000000000000000000000000000000000000', '0x0000000000000000000000000000000000000000'], '0x0000000000000000000000000000000000000000', 25000]
        )
        await token.transfer(bancorHandler.address, 25000, { gasPrice: 0 })
        const result = await bancorHandler.performOrder.call(encodedPayload, 25000, 25000, { from: accounts[2], gasPrice: 0 });
        assert.equal(result.amountSpentOnOrder.toString(), "25000")
        assert.equal(result.amountReceivedFromOrder.toString(), "49950")
        await bancorHandler.performOrder(encodedPayload, 25000, 25000, { from: accounts[2], gasPrice: 0 });
        assert.equal(await web3.eth.getBalance(accounts[2]), "49950")
    })

})


const HANDLER_DATA_ABI =
    ['address', 'address[7]', 'address', 'uint256']