const KyberHandler = artifacts.require("KyberHandler")

const ethereumMainnetKyber = "0x9AAb3f75489902f3a48495025729a0AF77d4b11e"
module.exports = async function (deployer, network, accounts) {
    if(network === "test" || network === "develop" || network == "development"){
        return
    }
    await deployer.deploy(KyberHandler, ethereumMainnetKyber)
}
