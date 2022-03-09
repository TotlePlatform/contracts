const ZeroExExchangeHandler = artifacts.require("ZeroExExchangeHandler")
const ZERO_EX_ADDRESS = "0x080bf510fcbf18b91105470639e9561022937712"
const WETH_ADDRESS = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"
module.exports = async function (deployer, network, accounts) {
    if(network === "test" || network === "develop" || network == "development"){
        return
    }
    await deployer.deploy(ZeroExExchangeHandler,  ZERO_EX_ADDRESS, WETH_ADDRESS, TOTLE_PRIMARY)
}
