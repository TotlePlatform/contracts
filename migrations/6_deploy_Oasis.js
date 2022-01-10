const OasisHandler = artifacts.require("OasisHandler")
const OASIS_ADDRESS = "0x794e6e91555438aFc3ccF1c5076A74F42133d08D"
const WETH_ADDRESS = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"

module.exports = async function (deployer, network, accounts) {
    if(network === "test" || network === "develop" || network == "development"){
        return
    }
    await deployer.deploy(OasisHandler, OASIS_ADDRESS, WETH_ADDRESS)
}
