var TotlePrimary = artifacts.require("TotlePrimary")
var MockHandler = artifacts.require("HandlerMock")
var ErrorReporter = artifacts.require("ErrorReporter")
var StandardToken = artifacts.require("StandardToken")
var Affiliate = artifacts.require("Affiliate")
var AffiliateRegistry = artifacts.require("AffiliateRegistry")
var TokenTransferProxyMock = artifacts.require("TokenTransferProxyMock")
var abiEncoder = require("web3-eth-abi")
var ethers = require("ethers")

contract('TotlePrimary', (accounts) => {
    var token,
        errorReporter,
        handlerMock,
        totlePrimary,
        tokenTransferProxyMock,
        affiliateRegistry,
        affiliateTarget

    beforeEach(async () => {
        affiliateTarget = await Affiliate.new()
        affiliateRegistry = await AffiliateRegistry.new(affiliateTarget.address, "0xEC3281124d4c2FCA8A88e3076C1E7749CfEcb7F2","10000000000000000")
        var affiliateAddress = ((await affiliateRegistry.registerAffiliate("0x0000000000000000000000000000000000000000", 0)).logs[0].args["0"])
        tokenTransferProxyMock = await TokenTransferProxyMock.new()
        token = await StandardToken.new(accounts[0], accounts[1])
        errorReporter = await ErrorReporter.new()
        totlePrimary = await TotlePrimary.new(tokenTransferProxyMock.address, affiliateRegistry.address, errorReporter.address, affiliateAddress)
        await web3.eth.sendTransaction({
            from: accounts[2],
            to: "0x0000000000000000000000000000000000000000",
            value: await web3.eth.getBalance(accounts[2]),
            gasPrice: 0
        })
    })

    it("test performRebalance() with normal buy order", async () => {
        handlerMock = await MockHandler.new(token.address, totlePrimary.address, errorReporter.address, 20)
        await totlePrimary.addHandlerToWhitelist(handlerMock.address)
        await token.transfer(handlerMock.address, 48333317481, {from: accounts[0]})
        await web3.eth.sendTransaction({from: accounts[0], to: accounts[2], value: 50000})
        var amountToGive = await totlePrimary.performRebalance([
            [
                false,
                token.address,
                10000,
                false,
                1,
                10000,
                [
                    [handlerMock.address, encodeOrder(20000)]
                ]
            ]
        ], "0x0000000000000000000000000000000000000000", "0x1111111111111111111111111111111111111111111111111111111111111111", {
            from: accounts[2],
            value: 50000,
            gasPrice: 0
        })
        assert.equal(await web3.eth.getBalance(accounts[2]), 39900)
        assert.equal(await token.balanceOf(accounts[2]), 200000)
    })

    it("test performRebalance() with normal sell order", async () => {
        handlerMock = await MockHandler.new(token.address, totlePrimary.address, errorReporter.address, 20)
        await totlePrimary.addHandlerToWhitelist(handlerMock.address)
        await token.transfer(accounts[2], 20000, {from: accounts[0]})
        await token.approve(tokenTransferProxyMock.address, 20000, {from: accounts[2], gasPrice: 0})
        await web3.eth.sendTransaction({from: accounts[0], to: handlerMock.address, value: 50000})
        var amountToGive = await totlePrimary.performRebalance([
            [
                true,
                token.address,
                10000,
                false,
                1,
                10000,
                [
                    [handlerMock.address, encodeOrder(20000)]
                ]
            ]
        ], "0x0000000000000000000000000000000000000000", "0x1111111111111111111111111111111111111111111111111111111111111111", {
            from: accounts[2],
            value: 0,
            gasPrice: 0
        })
        assert.equal(await web3.eth.getBalance(accounts[2]), 495)
        assert.equal(await token.balanceOf(accounts[2]), 10000)
    })

})

function encodeOrder(order) {
    return abiEncoder.encodeParameters(["uint256"], [order])
}
