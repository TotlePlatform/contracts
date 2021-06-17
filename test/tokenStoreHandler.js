var TokenStoreHandler = artifacts.require("TokenStoreHandler")
var TokenStoreMock = artifacts.require("TokenStoreMock")
var ErrorReporter = artifacts.require("ErrorReporter")
var StandardToken = artifacts.require("StandardToken")
let abiEncoder = require("web3-eth-abi")
let ethers = require("ethers")

contract('TokenStoreHandler', (accounts) => {
    var token,
        errorReporter,
        tokenStoreMock,
        tokenStoreHandler
    var BUY_ORDER
    var SELL_ORDER
    beforeEach(async () => {
        token = await StandardToken.new(accounts[0], accounts[1])
        errorReporter = await ErrorReporter.new()
        tokenStoreMock = await TokenStoreMock.new(web3.utils.toWei("0.001", "ether"))
        tokenStoreHandler = await TokenStoreHandler.new(tokenStoreMock.address, accounts[0], errorReporter.address)
        BUY_ORDER = await signAndEncodeOrder({
            takerToken: token.address,
            takerAmount: "5000000000",
            makerToken: "0x0000000000000000000000000000000000000000",
            makerAmount: "10000000000",
            expires: "444999944",
            nonce: 3,
            user: accounts[1]
        }, tokenStoreMock.address)
        SELL_ORDER = await signAndEncodeOrder({
            takerToken: "0x0000000000000000000000000000000000000000",
            takerAmount: "10000000000",
            makerToken: token.address,
            makerAmount: "5000000000",
            expires: "444999944",
            nonce: 3,
            user: accounts[1]
        }, tokenStoreMock.address)
    })

    it("test getAmountToGive() with buy order and low maker balance", async () => {
        await tokenStoreMock.deposit({from: accounts[1], value: 1000000000})
        var amountToGive = await tokenStoreHandler.getAmountToGive(BUY_ORDER, {from: accounts[0]})
        assert.equal(amountToGive.toString(), "500500000")
    })

    it("test getAmountToGive() with buy order", async () => {
        await tokenStoreMock.deposit({from: accounts[1], value: 10000000000})
        var amountToGive = await tokenStoreHandler.getAmountToGive(BUY_ORDER)
        assert.equal(amountToGive.toString(), "5005000000")
    })

    it("test getAmountToGive() with sell order and low maker balance tokens", async () => {
        await token.approve(tokenStoreMock.address, 500000000, {from: accounts[1]})
        await tokenStoreMock.depositToken(token.address, 500000000, {from: accounts[1]})
        var amountToGive = await tokenStoreHandler.getAmountToGive(SELL_ORDER)

        assert.equal(amountToGive.toString(), "1001000000")
    })

    it("test getAmountToGive() with sell order", async () => {
        await token.approve(tokenStoreMock.address, 5000000000, {from: accounts[1]})
        await tokenStoreMock.depositToken(token.address, 5000000000, {from: accounts[1]})
        var amountToGive = await tokenStoreHandler.getAmountToGive(SELL_ORDER)
        assert.equal(amountToGive.toString(), "10010000000")
    })

    it("test staticChecks() - clean", async () => {
        var result = await tokenStoreHandler.methods["staticExchangeChecks(bytes)"].call(BUY_ORDER)
        assert.equal(result, true)
    })

    it("test staticChecks() - Bad signature", async () => {
        var order = {
            takerToken: "0x0000000000000000000000000000000000000000",
            takerAmount: "10000000000",
            makerToken: token.address,
            makerAmount: "5000000000",
            expires: "444999944",
            nonce: 3,
            user: accounts[1]
        }
        var orderHash = getOrderHash(order, tokenStoreMock.address)
        var signature = await getSignature(accounts[1], orderHash)
        order.v = signature.v
        order.r = signature.r
        order.s = "0xd18cec4907b50f4eda4a197a50b61974921b4d197a50b619741e921b4d111111"

        var result = await tokenStoreHandler.methods["staticExchangeChecks(bytes)"].call(encodeOrder(order))

        assert.equal(result, false)
    })

    it("test performBuyOrder() - clean", async () => {
        await token.approve(tokenStoreMock.address, 5000000000, {from: accounts[1]})
        await tokenStoreMock.depositToken(token.address, 5000000000, {from: accounts[1]})

        var result = await tokenStoreHandler.methods["performBuyOrder(bytes,uint256)"].call(SELL_ORDER, 10000000000, {
            value: 10000000000,
            from: accounts[0]
        })

        assert.equal(result.amountSpentOnOrder.toString(), "10000000000")
        assert.equal(result.amountReceivedFromOrder.toString(), "4995004995")
    })

    it("test performSellOrder() - clean", async () => {
        await token.transfer(tokenStoreHandler.address, 5000000000, {from: accounts[0]})
        await tokenStoreMock.deposit({from: accounts[1], value: 100000000000})

        var result = await tokenStoreHandler.methods["performSellOrder(bytes,uint256)"].call(BUY_ORDER, 5000000000, {
            value: 0,
            from: accounts[0]
        })

        assert.equal(result.amountSpentOnOrder.toString(), "5000000000")
        assert.equal(result.amountReceivedFromOrder.toString(), "9990009990")
    })

})

async function signAndEncodeOrder(order, exchangeAddress) {
    var signature = await getSignature(order.user, getOrderHash(order, exchangeAddress))
    order.v = signature.v
    order.r = signature.r
    order.s = signature.s
    return encodeOrder(order)
}

async function getSignature(account, orderHash) {
    var packedSignature = await web3.eth.sign(orderHash, account)
    return ethers.utils.splitSignature(packedSignature)
}

function getOrderHash(order, exchangeAddress) {
    const orderHash = ethers.utils.soliditySha256([
        "address",
        "address",
        "uint256",
        "address",
        "uint256",
        "uint256",
        "uint256"
    ], [
        exchangeAddress,
        order.takerToken,
        order.takerAmount,
        order.makerToken,
        order.makerAmount,
        order.expires,
        order.nonce
    ])
    return orderHash
}

function encodeOrder(order) {
    return abiEncoder.encodeParameters([
        "address",
        "uint256",
        "address",
        "uint256",
        "uint256",
        "uint256",
        "address",
        "uint8",
        "bytes32",
        "bytes32"
    ], [
        order.takerToken,
        order.takerAmount,
        order.makerToken,
        order.makerAmount,
        order.expires,
        order.nonce,
        order.user,
        order.v,
        order.r,
        order.s
    ])
}
