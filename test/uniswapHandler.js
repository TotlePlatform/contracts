const UniswapHandler = artifacts.require("UniswapHandler")
const UniswapMock = artifacts.require("UniswapMock")
const ErrorReporter = artifacts.require("ErrorReporter")
const StandardToken = artifacts.require("StandardToken")
const AbiEncoder = require("web3-eth-abi")

contract('UniswapHandler', (accounts) => {
    var token,
        errorReporter,
        uniswapMock,
        uniswapHandler
    var BUY_ORDER
    var SELL_ORDER

    beforeEach(async () => {
        token = await StandardToken.new(accounts[0], accounts[1])
        errorReporter = await ErrorReporter.new()
        uniswapMock = await UniswapMock.new(token.address)
        uniswapHandler = await UniswapHandler.new(accounts[0], errorReporter.address)
        await uniswapMock.depositEth({value: 20000000000, from: accounts[1]});
        await token.approve(uniswapMock.address, 10000000000, {from:accounts[1]})
        await uniswapMock.depositTokens(10000000000, {from: accounts[1]});
        BUY_ORDER = encodeOrder({exchangeAddress: uniswapMock.address, amountToGive: 1000000})
        SELL_ORDER = encodeOrder({exchangeAddress: uniswapMock.address, amountToGive: 1000000})
    })

    it("test getAmountToGive() with buy order", async () => {
        var amountToGive = await uniswapHandler.getAmountToGive(BUY_ORDER)
        assert.equal(amountToGive.toString(), "1000000")
    })

    it("test getAmountToGive() with sell order", async () => {
        var amountToGive = await uniswapHandler.getAmountToGive(SELL_ORDER)

        assert.equal(amountToGive.toString(), "1000000")
    })

    it("test staticChecks() - clean", async () => {
        var result = await uniswapHandler.methods["staticExchangeChecks(bytes)"](BUY_ORDER)
        assert.equal(result, true)
    })

    it("test performBuyOrder() - clean", async () => {
        var result = await uniswapHandler.methods["performBuyOrder(bytes,uint256)"].call(SELL_ORDER, 1000000, {
            value: 1000000,
            from: accounts[0]
        })
        assert.equal(result.amountSpentOnOrder.toString(), "1000000")
        assert.equal(result.amountReceivedFromOrder.toString(), "498475")
    })

    it("test performSellOrder() - clean", async () => {
        token.transfer(uniswapHandler.address, 1000000, {from: accounts[0]})
        var result = await uniswapHandler.methods["performSellOrder(bytes,uint256)"].call(BUY_ORDER, 1000000, {
            value: 0,
            from: accounts[0]
        })
        assert.equal(result.amountSpentOnOrder.toString(), "1000000")
        assert.equal(result.amountReceivedFromOrder.toString(), "1993801")
    })
})

function encodeOrder(order) {
    return AbiEncoder.encodeParameters([
        "address", "uint256"
    ], [order.exchangeAddress, order.amountToGive])
}
