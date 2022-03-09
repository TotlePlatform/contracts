const TotlePrimary = artifacts.require("TotlePrimary")
const TokenTransferProxy = artifacts.require("TokenTransferProxy")
const SIGNER_ADDRESS = "0xC2D7CF95645D33006175B78989035C7c9061d3F9"
const ZeroExExchangeHandler = artifacts.require("ZeroExExchangeHandler")
module.exports = async function (deployer, network, accounts) {
    if(network === "test" || network === "develop" || network == "development"){
        return
    }
    const tokenTransferProxy = await TokenTransferProxy.deployed()
    const zeroEx = await ZeroExExchangeHandler.deployed()
    await deployer.deploy(TotlePrimary, TokenTransferProxy.address, SIGNER_ADDRESS)
    await tokenTransferProxy.addAuthorizedAddress(TotlePrimary.address)
    await zeroEx.addTotle(TotlePrimary.address)
}
