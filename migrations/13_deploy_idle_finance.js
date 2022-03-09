const IdleFinanceHandler = artifacts.require("IdleFinanceHandler")
module.exports = async function (deployer, network, accounts) {
    if(network === "test" || network === "develop" || network == "development"){
        return
    }
    await deployer.deploy(IdleFinanceHandler)
}
