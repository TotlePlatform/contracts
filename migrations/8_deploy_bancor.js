const BancorHandler = artifacts.require("BancorHandler")

module.exports = async function (deployer, network, accounts) {
    if(network === "test" || network === "develop" || network == "development"){
        return
    }
    await deployer.deploy(BancorHandler)
}
