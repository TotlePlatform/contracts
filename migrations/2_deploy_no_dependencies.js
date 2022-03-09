const TokenTransferProxy = artifacts.require("TokenTransferProxy")
const Partner = artifacts.require("Partner")
const PartnerRegistry = artifacts.require("PartnerRegistry")
const TOTLE_BENEFICIARY = "0x583d03451406d179182efc742a1d811a9e34c36b"
const BASE_PERCENTAGE = "2500000000000000"
const PREVIOUS_REGISTRY = "0xf3e5e76dabc9f4c479c258b4d7bb2f8250a8819c"

module.exports = async function (deployer, network, accounts) {
    if(network === "test" || network === "develop" || network == "development"){
        return
    }
    await deployer.deploy(TokenTransferProxy)
    await deployer.deploy(Partner)
    await deployer.deploy(PartnerRegistry, PREVIOUS_REGISTRY, Partner.address, TOTLE_BENEFICIARY, BASE_PERCENTAGE)
}
