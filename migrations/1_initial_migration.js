const Migrations = artifacts.require("./Migrations.sol")

module.exports = async function (deployer, network) {
    // if(network === "test" || network === "develop" || network == "development"){
    //     return
    // }
    await deployer.deploy(Migrations)
}
