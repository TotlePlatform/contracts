const TotlePrimary = artifacts.require("TotlePrimary")
const MockHandler = artifacts.require("HandlerMock")
const StandardToken = artifacts.require("StandardToken")
const Partner = artifacts.require("Partner")
const PartnerRegistry = artifacts.require("PartnerRegistry")
const TokenTransferProxyMock = artifacts.require("TokenTransferProxyMock")
const keccak256 = require('web3-utils').keccak256
var AbiEncoder = require("web3-eth-abi")

contract('TotlePrimary', (accounts) => {
    var token,
        handlerMock,
        totlePrimary,
        tokenTransferProxyMock,
        partnerRegistry,
        partnerTarget,
        partnerAddress

    beforeEach(async () => {
        partnerTarget = await Partner.new()
        partnerRegistry = await PartnerRegistry.new("0x0000000000000000000000000000000000000000", partnerTarget.address, accounts[2], "10000000000000000")
        partnerAddress = ((await partnerRegistry.registerPartner("0x0000000000000000000000000000000000000000", 0)).logs[0].args["2"])
        tokenTransferProxyMock = await TokenTransferProxyMock.new()
        token = await StandardToken.new(accounts[0], accounts[1])
        totlePrimary = await TotlePrimary.new(tokenTransferProxyMock.address, '0x19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A')
        await web3.eth.sendTransaction({
            from: accounts[2],
            to: "0x0000000000000000000000000000000000000000",
            value: await web3.eth.getBalance(accounts[2]),
            gasPrice: 0
        })
    })

    it("test performSwapCollection() with an order", async () => {
        handlerMock = await MockHandler.new(token.address, 20)
        await token.transfer(handlerMock.address, "1000000000000000000", { from: accounts[0] })
        await web3.eth.sendTransaction({ from: accounts[0], to: accounts[2], value: 50000 })
        await web3.eth.sendTransaction({ from: accounts[0], to: handlerMock.address, value: "1000000000000000000" })
        const chainId = await web3.eth.getChainId()
        const payload = createPayload(chainId, [{
            trades: [
                {
                    sourceToken: '0x0000000000000000000000000000000000000000', destinationToken: token.address, amount: 50000, orders: [{
                        exchangeHandler: handlerMock.address,
                        encodedPayload: AbiEncoder.encodeParameters(
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
                    }]
                }
            ], minimumDestinationAmount: 0, minimumExchangeRate: 0, sourceAmount: 50000, tradeToTakeFeeFrom: 0, takeFeeFromSource: true, redirectAddress: '0x0000000000000000000000000000000000000000'
        }], partnerAddress, 20000000, "100000000000000000", '0x00000000000000000000000000000000000000000000000000edcba987654321', accounts[2])
        let results
        results = await totlePrimary.performSwapCollection(
            payload,
            {
                from: accounts[2],
                value: 50000,
                gasPrice: 0
            })
        assert.equal(await web3.eth.getBalance(accounts[2]), 0)
        assert.equal(parseInt((await token.balanceOf(accounts[2])).toString()), "990000")
    })
})

const SIGNATURE_HASH_COMPONENT_ABI = [{ "name": "chainId", "type": "uint256" }, { "components": [{ "components": [{ "name": "sourceToken", "type": "address" }, { "name": "destinationToken", "type": "address" }, { "name": "amount", "type": "uint256" }, { "components": [{ "name": "exchangeHandler", "type": "address" }, { "name": "encodedPayload", "type": "bytes" }], "name": "orders", "type": "tuple[]" }], "name": "trades", "type": "tuple[]" }, { "name": "minimumExchangeRate", "type": "uint256" }, { "name": "minimumDestinationAmount", "type": "uint256" }, { "name": "sourceAmount", "type": "uint256" }, { "name": "tradeToTakeFeeFrom", "type": "uint256" }, { "name": "takeFeeFromSource", "type": "bool" }, { "name": "redirectAddress", "type": "address" }], "name": "swaps", "type": "tuple[]" }, { "name": "partnerContract", "type": "address" }, { "name": "expirationBlock", "type": "uint256" }, { "name": "id", "type": "bytes32" }, { "name": "maxGasPrice", "type": "uint256" }, { "name": "sender", "type": "address" }]

function signPayload(chainId, swaps, partnerContract, expirationBlock, maxGasPrice, id, userAddress) {
    let hash = keccak256(
        AbiEncoder.encodeParameters(
            SIGNATURE_HASH_COMPONENT_ABI,
            [
                chainId,
                swaps,
                partnerContract,
                expirationBlock,
                id,
                maxGasPrice,
                userAddress
            ]
        )
    )
    const signature = web3.eth.accounts.sign(hash, '0x1111111111111111111111111111111111111111111111111111111111111111')

    return { v: parseInt(signature.v), r: signature.r, s: signature.s }
}

function createPayload(chainId, swaps, partnerContract, expirationBlock, maxGasPrice, id, userAddress) {
    const signature = signPayload(chainId, swaps, partnerContract, expirationBlock, maxGasPrice, id, userAddress)

    return { swaps, expirationBlock, id, maxGasPrice, partnerContract, tokenCount: 2, v: signature.v, r: signature.r, s: signature.s }
}