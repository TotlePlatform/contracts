const CurveFiHandler = artifacts.require("CurveFiHandler")
module.exports = async function (deployer, network, accounts) {
    if(network === "test" || network === "develop" || network == "development"){
        return
    }
    await deployer.deploy(CurveFiHandler)
}
