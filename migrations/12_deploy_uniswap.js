const UniswapHandler = artifacts.require("UniswapHandler")
const UNISWAP_FACTORY_ADDRESS = "0xc0a47dFe034B400B47bDaD5FecDa2621de6c4d95"
module.exports = async function (deployer, network, accounts) {
    if(network === "test" || network === "develop" || network == "development"){
        return
    }
    await deployer.deploy(UniswapHandler, UNISWAP_FACTORY_ADDRESS)
}
