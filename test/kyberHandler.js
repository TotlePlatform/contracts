const KyberHandler = artifacts.require("KyberHandler")
const KyberMock = artifacts.require("KyberMock")
const StandardToken = artifacts.require("StandardToken")
const AbiEncoder = require("web3-eth-abi")
const ProxyTransferTester = artifacts.require("ProxyTransferTester")

contract('KyberHandler', (accounts) => {
    var token,
        kyberMock,
        kyberHandler,
        proxyTransferTester

    beforeEach(async () => {
        proxyTransferTester = await ProxyTransferTester.new()
        token = await StandardToken.new(accounts[0], accounts[1])
        kyberMock = await KyberMock.new(token.address)
        kyberHandler = await KyberHandler.new(kyberMock.address)
        await proxyTransferTester.transferETH(accounts[0], { value: (await web3.eth.getBalance(accounts[2])).toString(), from: accounts[2], gasPrice: 0 })

        await token.transfer(kyberMock.address, 10000000000, { from: accounts[0], gasPrice: 0 })
        await proxyTransferTester.transferETH(kyberMock.address, { value: "100000000", from: accounts[0], gasPrice: 0 })
    })

    it("test performOrder() - eth -> token", async () => {
        const encodedPayload = AbiEncoder.encodeParameter(
            HANDLER_DATA_ABI,
            { tokenFrom: "0x0000000000000000000000000000000000000000", tokenTo: token.address, maxSpend: 50000, hint: "0x" }
        )
        await proxyTransferTester.transferETH(kyberHandler.address, { value: 50000, gasPrice: 0 })
        const result = await kyberHandler.performOrder.call(encodedPayload, 50000, 50000, { from: accounts[2], gasPrice: 0 });
        assert.equal(result.amountSpentOnOrder.toString(), "50000")
        assert.equal(result.amountReceivedFromOrder.toString(), "24975")
        await kyberHandler.performOrder(encodedPayload, 50000, 50000, { from: accounts[2], gasPrice: 0 });
        assert.equal((await token.balanceOf(accounts[2])).toString(), "24975")
    })


    it("test performOrder() - token -> eth", async () => {
        const encodedPayload = AbiEncoder.encodeParameter(
            HANDLER_DATA_ABI,

            { tokenFrom: token.address, tokenTo: "0x0000000000000000000000000000000000000000", maxSpend: 25000, hint: "0x" }
        )
        await token.transfer(kyberHandler.address, 25000, { gasPrice: 0 })
        const result = await kyberHandler.performOrder.call(encodedPayload, 25000, 25000, { from: accounts[2], gasPrice: 0 });
        assert.equal(result.amountSpentOnOrder.toString(), "25000")
        assert.equal(result.amountReceivedFromOrder.toString(), "49950")
        await kyberHandler.performOrder(encodedPayload, 25000, 25000, { from: accounts[2], gasPrice: 0 });
        assert.equal(await web3.eth.getBalance(accounts[2]), "49950")
    })

})


const HANDLER_DATA_ABI = {
    name: 'OrderData',
    type: 'tuple',
    components:

        [{ name: 'tokenFrom', type: 'address' },
        { name: 'tokenTo', type: 'address' },
        { name: 'maxSpend', type: 'uint256' },
        { name: 'hint', type: 'bytes' }]
}