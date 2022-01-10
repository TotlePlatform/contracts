/**
 * Use this file to configure your truffle project. It's seeded with some
 * common settings for different networks and features like migrations,
 * compilation and testing. Uncomment the ones you need or modify
 * them to suit your project as necessary.
 *
 * More information about configuration can be found at:
 *
 * truffleframework.com/docs/advanced/configuration
 *
 * To deploy via Infura you'll need a wallet provider (like truffle-hdwallet-provider)
 * to sign your transactions before they're sent to a remote public node. Infura API
 * keys are available for free at: infura.io/register
 *
 *   > > Using Truffle V5 or later? Make sure you install the `web3-one` version.
 *
 *   > > $ npm install truffle-hdwallet-provider@web3-one
 *
 * You'll also need a mnemonic - the twelve word phrase the wallet uses to generate
 * public/private key pairs. If you're publishing your code to GitHub make sure you load this
 * phrase from a file you've .gitignored so it doesn't accidentally become public.
 *
 */

// Note: not sure if we still need babel.

    // require('babel-register')({
    //     ignore: /node_modules\/(?!openzeppelin-solidity)/
    // });
    // require('babel-polyfill');

var HDWalletProvider = require("@truffle/hdwallet-provider")
var NonceTrackerSubprovider = require("web3-provider-engine/subproviders/nonce-tracker")

const rpcNode = ""
const fs = require('fs'); const mnemonic = fs.readFileSync(".secret").toString().trim();

const gasLimitToUse = 3000000
const gasPriceToUse = 150000000000
const deployingAddress = ""

module.exports = {
    /**
     * Networks define how you connect to your ethereum client and let you set the
     * defaults web3 uses to send transactions. If you don't specify one truffle
     * will spin up a development blockchain for you on port 9545 when you
     * run `develop` or `test`. You can ask a truffle command to use a specific
     * network from the command line, e.g
     *
     * $ truffle test --network <network-name>
     */

    networks: {
        // Useful for testing. The `development` name is special - truffle uses it by default
        // if it's defined here and no other network is specified at the command line.
        // You should run a client (like ganache-cli, geth or parity) in a separate terminal
        // tab if you use this network and you must also set the `host`, `port` and `network_id`
        // options below to some value.

//        development: {
//            host: "localhost",
//            port: 8545, // Using ganache as development network
//            network_id: "*",
//            gasPrice: gasPriceToUse,
//            gas: gasLimitToUse,
//        },

        mainnet: {
            provider: function () {
                var wallet = new HDWalletProvider(
                          mnemonic,
                          rivetNode,
                          1 // index of account
                      )
                var nonceTracker = new NonceTrackerSubprovider()
                wallet.engine._providers.unshift(nonceTracker)
                nonceTracker.setEngine(wallet.engine)
                return wallet
            },
            network_id: 1,
            gasPrice: gasPriceToUse,
            gas: gasLimitToUse,
            websockets: true,
            confirmations: 0,       // # of confs to wait between deployments. (default: 0)
            timeoutBlocks: 100,     // # of blocks before a deployment times out  (minimum/default: 50)
            skipDryRun: true,        // Skip dry run before migrations? (default: false for public nets )
            networkCheckTimeout:10000
        }
    },


    // Configure your compilers
    compilers: {
        solc: {
            version: "0.8.9",   // Fetch exact version from solc-bin (default: truffle's version)
                docker: false,        // Use "0.5.1" you've installed locally with docker (default: false)
                settings: {
                    optimizer: {
                        enabled: true, // Default: false
                         runs: 999     // Default: 200
                    }
            }
        },
    }
}
