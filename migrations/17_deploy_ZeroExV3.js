const ZeroExV3ExchangeHandler = artifacts.require("ZeroExV3ExchangeHandler")
const ZERO_EX_ADDRESS = "0x61935cbdd02287b511119ddb11aeb42f1593b7ef"
const WETH_ADDRESS = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"

module.exports = async function (deployer, network, accounts) {
    if (network === "test" || network === "develop" || network == "development") {
        return
    }
    await deployer.deploy(ZeroExV3ExchangeHandler, ZERO_EX_ADDRESS, WETH_ADDRESS)
}
