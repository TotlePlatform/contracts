var WeiDexHandler = artifacts.require("WeiDexHandler")
var WeiDexMock = artifacts.require("WeiDexMock")
var ErrorReporter = artifacts.require("ErrorReporter")
var StandardToken = artifacts.require("StandardToken")
let abiEncoder = require("web3-eth-abi")
let ethers = require("ethers")

contract('WeiDexHandler', (accounts) => {
    var token, errorReporter, weiDexMock, weiDexHandler
    var BUY_ORDER
    var SELL_ORDER
    beforeEach(async () => {
        token = await StandardToken.new(accounts[0], accounts[1])
        errorReporter = await ErrorReporter.new()
        weiDexMock = await WeiDexMock.new("0x0000000000000000000000000000000000000000", 1000)
        await token.approve(weiDexMock.address, "10000000000000000000000", {from: accounts[1]})
        await weiDexMock.depositTokens(token.address, "50000000000000000", {from: accounts[1]})
        weiDexHandler = await WeiDexHandler.new(weiDexMock.address, accounts[0], errorReporter.address)
        BUY_ORDER  = await signAndEncodeOrder({
            addresses: [accounts[0], "0x0000000000000000000000000000000000000000", token.address],
            values: [5635346, 1127069200, 5151245]
        }, weiDexMock.address)
        SELL_ORDER = await signAndEncodeOrder({
            addresses: [accounts[1], token.address, "0x0000000000000000000000000000000000000000"],
            values: [943656800, 4718284, 5152241]
        }, weiDexMock.address)
    })

    it("test getAmountToGive() with buy order and low maker balance", async () => {
        await weiDexMock.depositEthers({from: accounts[0], value: 99999})
        var amountToGive = await weiDexHandler.getAmountToGive(BUY_ORDER)
        assert.equal(amountToGive.toString(), "19979800")
    })

    it("test getAmountToGive() with buy order", async () => {
        await weiDexMock.depositEthers({from: accounts[0], value: 346346234765334})
        var amountToGive = await weiDexHandler.getAmountToGive(BUY_ORDER)
        assert.equal(amountToGive.toString(), "1127069200")
    })

    it("test getAmountToGive() with sell order and low maker balance tokens", async () => {
        await weiDexMock.withdrawTokens(token.address, 49999999000, {from: accounts[1]})
        var amountToGive = await weiDexHandler.getAmountToGive(SELL_ORDER)

        assert.equal(amountToGive.toString(), "4718284")
    })

    it("test getAmountToGive() with sell order", async () => {
        var amountToGive = await weiDexHandler.getAmountToGive(SELL_ORDER)

        assert.equal(amountToGive.toString(), "4718284")
    })

    it("test staticChecks() - clean", async () => {
        var result = await weiDexHandler.staticExchangeChecks(BUY_ORDER)
        assert.equal(result, true)
    })
    it("test staticChecks() - filled order", async () => {
        var FILLED_ORDER =  await signAndEncodeOrder({
            addresses: [accounts[1], token.address, "0x0000000000000000000000000000000000000000"],
            values: [943656800, 0, 5152245]
        }, weiDexMock.address)

        var result = await weiDexHandler.staticExchangeChecks(FILLED_ORDER)

        assert.equal(result, false)
    })

    it("test staticChecks() - Bad signature", async () => {
        var order = {
            addresses: [accounts[1], token.address, "0x0000000000000000000000000000000000000000"],
            values: [943656800, 4718284, 5152245]
        }
        var orderHash = getOrderHash(order, weiDexMock.address);
        var signature = await getSignature(accounts[1], orderHash);
        order.v=signature.v
        order.r=signature.r
        order.s="0xd18cec4907b50f4eda4a197a50b61974921b4d197a50b619741e921b4d111111"

        var result = await weiDexHandler.staticExchangeChecks(encodeOrder(order))

        assert.equal(result, false)
    })

    it("test performBuyOrder() - clean", async () => {
        var result = await weiDexHandler.methods["performBuyOrder(bytes,uint256)"].call(SELL_ORDER, 401000, {value: 401000, from: accounts[0]})

        assert.equal(result.amountSpentOnOrder.toString(), "401000")
        assert.equal(result.amountReceivedFromOrder.toString(), "80119800")
    })

    it("test performSellOrder() - clean", async () => {
        //Need to recreate the weiDexHandler with the account[1] as the totlePrimary, since that's the account we're testing from
        weiDexHandler = await WeiDexHandler.new(weiDexMock.address, accounts[1], errorReporter.address)
        await token.transfer(weiDexHandler.address, 49193, {from: accounts[1]})
        await weiDexMock.depositEthers({from: accounts[0], value: 346346234765334})
        var result = await weiDexHandler.methods["performSellOrder(bytes,uint256)"].call(BUY_ORDER, 49193, {value: 0, from: accounts[1]})

        assert.equal(result.amountSpentOnOrder.toString(), "49193")
        assert.equal(result.amountReceivedFromOrder.toString(), "245")
    })

})

async function signAndEncodeOrder(order, exchangeAddress){
    var signature = await getSignature(order.addresses[0], getOrderHash(order, exchangeAddress),)
    order.v = signature.v
    order.r = signature.r
    order.s = signature.s
    return encodeOrder(order)
}

async function getSignature(account, orderHash){
    var packedSignature = await web3.eth.sign(orderHash,account)
    return ethers.utils.splitSignature(packedSignature)
}

function getOrderHash(order, exchangeAddress) {
    const orderHash = ethers.utils.solidityKeccak256(
        ["address", "address", "uint256", "address", "uint256", "uint256", "address"],
        [order.addresses[0], order.addresses[1], order.values[0], order.addresses[2], order.values[1], order.values[2], exchangeAddress]
    )
    return orderHash
}


function encodeOrder(order){
    return abiEncoder.encodeParameters(["address[3]", "uint256[3]", "uint8", "bytes32", "bytes32"],
                                       [ order.addresses, order.values, order.v, order.r, order.s])
}
