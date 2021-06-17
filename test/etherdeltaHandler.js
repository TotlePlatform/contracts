// var EtherDeltaHandler = artifacts.require("EtherDeltaHandler");
// var EtherDeltaSelectorProvider = artifacts.require("EtherDeltaSelectorProvider");
// var EtherDeltaMock = artifacts.require("EtherDeltaMock");
// var ErrorReporter = artifacts.require("ErrorReporter");
// var Logger = artifacts.require("Logger");
// var StandardToken = artifacts.require("StandardToken");
// var WETH = artifacts.require("WETH");
// var ethjsutil = require("ethereumjs-util");
// let abiEncoder = require("web3-eth-abi");
// let ethers = require("ethers");
// function encodeOrder(tokenGet, amountGet, tokenGive, amountGive, expires, nonce, user, v, r, s, exchangeFee){
//     return abiEncoder.encodeParameters(["address", "address", "address", "uint256", "uint256", "uint256", "uint256", "uint8", "bytes32", "bytes32", "uint256"],
//                                         [user,      tokenGive, tokenGet,  amountGive,amountGet, expires,   nonce,     v,       r,         s,         exchangeFee])
// }
//
// contract('EtherDeltaHandler', (accounts) => {
//     var token;
//     var errorReporter;
//     var logger;
//     var etherDeltaSelectorProvider;
//     var etherDeltaMock;
//     var etherDeltaHandler;
//     var BUY_ORDER;
//     var SELL_ORDER;
//     beforeEach(async () => {
//         token = await StandardToken.new(accounts[0], accounts[1]);
//         errorReporter = await ErrorReporter.new();
//         logger = await Logger.new();
//         etherDeltaSelectorProvider = await EtherDeltaSelectorProvider.new();
//         etherDeltaMock = await EtherDeltaMock.new();
//         await token.approve(etherDeltaMock.address,1000, {from: accounts[1]});
//         await etherDeltaMock.depositToken(token.address, 1000, {from: accounts[1]});
//         etherDeltaHandler = await EtherDeltaHandler.new(etherDeltaMock.address, etherDeltaSelectorProvider.address, accounts[0], errorReporter.address, logger.address);
//         SELL_ORDER = encodeOrder(token.address, 2000, "0x0000000000000000000000000000000000000000", 800, 1000000, 58219, accounts[1],2,"0x2dd62c442bb6f8e27da2f494aa3b60443d3b998fbb02ed8a1b7a004803d600c8","0x2dd62c442bb6f8e27da2f494aa3b60443d3b998fbb02ed8a1b7a004803d600c8",3000000000000000);
//         BUY_ORDER = encodeOrder("0x0000000000000000000000000000000000000000", 800, token.address, 2000, 1000000, 58219, accounts[1],2,"0x2dd62c442bb6f8e27da2f494aa3b60443d3b998fbb02ed8a1b7a004803d600c8","0x2dd62c442bb6f8e27da2f494aa3b60443d3b998fbb02ed8a1b7a004803d600c8",3000000000000000);
//     });
//
//     it("test getAmountToGive()", async () => {
//         var availableVolume = await etherDeltaMock.availableVolume("0x0000000000000000000000000000000000000000", 800, token.address, 2000, 1000000, 58219, accounts[1],2,"0x2dd62c442bb6f8e27da2f494aa3b60443d3b998fbb02ed8a1b7a004803d600c8","0x2dd62c442bb6f8e27da2f494aa3b60443d3b998fbb02ed8a1b7a004803d600c8");
//         var amountToGive = await etherDeltaHandler.getAmountToGive(BUY_ORDER);
//
//         assert.equal(amountToGive.toString(), "401");
//     });
//
//     it("test staticChecks() - clean", async () => {
//         var result = await etherDeltaHandler.staticExchangeChecks(BUY_ORDER);
//         assert.equal(result, true);
//     });
//
//     it("test staticChecks() - expiration", async () => {
//         var badOrder = encodeOrder("0x0000000000000000000000000000000000000000", 800,token.address, 2000, 1, 58219, accounts[1],2,"0x2dd62c442bb6f8e27da2f494aa3b60443d3b998fbb02ed8a1b7a004803d600c8","0x2dd62c442bb6f8e27da2f494aa3b60443d3b998fbb02ed8a1b7a004803d600c8",3000000000000000);
//         var result = await etherDeltaHandler.staticExchangeChecks(badOrder);
//         assert.equal(result, false);
//     });
//
//     it("test dynamicExchangeChecks() - high amountToSpend", async () => {
//         var result =  await etherDeltaHandler.methods["dynamicExchangeChecks(bytes,uint256)"](BUY_ORDER, 800);
//         assert.equal(result.amountSpentOnOrder.toString(), "401");
//         assert.equal(result.amountReceivedFromOrder.toString(), "1000");
//     });
//
//     it("test dynamicExchangeChecks() - low amountToSpend", async () => {
//         var result =  await etherDeltaHandler.methods["dynamicExchangeChecks(bytes,uint256)"](BUY_ORDER, 160);
//         assert.equal(result.amountSpentOnOrder.toString(), "160");
//         assert.equal(result.amountReceivedFromOrder.toString(), "400");
//     });
//
//     it("test performBuyOrder() - clean", async () => {
//         var result =  await etherDeltaHandler.methods["performBuyOrder(bytes,uint256)"].call(BUY_ORDER, 401, {value:401});
//         console.log(result);
//         assert.equal(result.amountSpentOnOrder.toString(), "401");
//         assert.equal(result.amountReceivedFromOrder.toString(), "1000");
//     });
//     it("test performBuyOrder() - amount to send != msg.value", async () => {
//         try {
//             var result =  await etherDeltaHandler.methods["performBuyOrder(bytes,uint256)"].call(BUY_ORDER, 401, {value:500});
//             assert.fail("Should have failed")
//         } catch(e){
//             if(e.actual === "Should have failed"){
//                 assert.fail("Should have reverted");
//             }
//         }
//
//     });
//     it.only("test performSellOrder() - clean", async () => {
//         await token.transfer(etherDeltaHandler.address, 1000, {from: accounts[0]});
//         var result = await etherDeltaHandler.methods["performSellOrder(bytes,uint256)"].call(SELL_ORDER, 100, {from:accounts[0], value:0});
//         console.log(result);
//
//     });
//
// })
//
// function findFunction(abi,signature){
//     return abi.find(function(functionAbi){
//         return functionAbi.signature === signature;
//     })
// }
