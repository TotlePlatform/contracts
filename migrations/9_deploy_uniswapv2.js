const UniswapV2Handler = artifacts.require("UniswapV2Handler")
module.exports = async function (deployer, network, accounts) {
    if(network === "test" || network === "develop" || network == "development"){
        return
    }
    await deployer.deploy(UniswapV2Handler)
}
