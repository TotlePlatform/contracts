/*
    For run tests it needs to be started in different terminals:

    1) ganache-cli --gasLimit 8000000 -f https://mainnet.infura.io/v3/c5c51292972442b780350d13af3ddeb7 -i 1 -e 10000 -p 8545 --chainId 1 --unlock 0x28C6c06298d514Db089934071355E5743bf21d60 0xf7cd385cb9a442358b892b14301f6310e57cc5c9 0x4f868c1aa37fcf307ab38d215382e88fca6275e2 0x7f4cbc1ff3763a8e2a147e8a93e8bcfcbdd45885
    2) npx truffle test --network mainnetFork

    With network in truffle-config.js:
    mainnetFork: {
      host: "127.0.0.1",
      port: "8545",
      gasPrice: 10,
      gas: 8e6,
      network_id: 1,
      skipDryRun: true,
      unlocked_accounts:["0x28C6c06298d514Db089934071355E5743bf21d60", "0xf7cd385cb9a442358b892b14301f6310e57cc5c9", "0xba12222222228d8ba445958a75a0704d566bf2c8", "0x7f4cbc1ff3763a8e2a147e8a93e8bcfcbdd45885"]
    }
*/


const Web3 = require('web3');
const web3 = new Web3(Web3.givenProvider || 'ws://localhost:8545');
const {
    balance,
    time} = require('@openzeppelin/test-helpers');
const BN = web3.utils.BN;
const { default: BigNumber } = require('bignumber.js');
/* Chai */
const { expect } = require('chai');
const truffleAssert = require("truffle-assertions");

const timeMachine = require('ganache-time-traveler');
const BalancerHandler = artifacts.require('BalancerV2Handler');
const TOKEN = artifacts.require('ERC20'); 
// MAINNET ADDRESSES
const balancerHandlerAddr = '0x8345454d4B70275B8806a84AF3bb810DD01DcD82';



const sleep = s => new Promise(resolve => setTimeout(resolve, 1000 * s));

describe('Fork test BalancerHandler', () => {
    let balancerHandler;
    let fromBlock;
    let dai, usdc, graph, enjin, weth;
    let holderDai, hoderUsdc, holderGraph, holderEnjin, holderWeth;

    let res;

    before(async() => {
        fromBlock = await web3.eth.getBlockNumber();
        [
            governance, strategist, user1, user2, rewards
        ] = await web3.eth.getAccounts();

        dai = await TOKEN.at('0x6B175474E89094C44Da98b954EedeAC495271d0F');
        usdc = await TOKEN.at('0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48');
        graph = await TOKEN.at('0xc944E90C64B2c07662A292be6244BDf05Cda44a7');
        enjin = await TOKEN.at('0xf629cbd94d3791c9250152bd8dfbdf380e2a3b9c');
        weth = await TOKEN.at('0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2');
        balancerHandler = await BalancerHandler.new('0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2');
        balancerHandler.sendTransaction({
            from:user2,
            value:10000000000000000000
        })
        console.log("Contract: ", balancerHandler.address);
        console.log("User: ", governance);

        holderDai = '0x28C6c06298d514Db089934071355E5743bf21d60';
        hoderUsdc = '0x28C6c06298d514Db089934071355E5743bf21d60';
        holderGraph = '0xf7cd385cb9a442358b892b14301f6310e57cc5c9';
        holderEnjin = '0x7f4cbc1ff3763a8e2a147e8a93e8bcfcbdd45885'
        holderWeth = '0x4f868c1aa37fcf307ab38d215382e88fca6275e2';
    

    });



    it('Perform order should working properly', async() => {
        let pool = '0x14462305d211c12a736986f4e8216e28c5ea7ab4';    //Weighted USDC--Graph
        let tokenOut = graph.address;
        let tokenIn = usdc.address;

        let res;
        let amountSpentOnOrder;
        let amountReceivedFromOrder;

        //await graph.transfer(balancerHandler.address, await graph.balanceOf(holderGraph), {from: holderGraph})

        await usdc.transfer(governance, Math.round((await usdc.balanceOf(hoderUsdc))/3), {from: hoderUsdc})
        //await usdc.transfer(balancerHandler.address, await usdc.balanceOf(hoderUsdc), {from: hoderUsdc})
        await usdc.approve(balancerHandler.address, await usdc.balanceOf(governance), {from: governance});        
                
        let availableToSpend = await usdc.balanceOf(governance);
        let targetAmount = 765113153;
        let targetAmountIsSource = true;

        console.log("STEP1 CONTRACT graph: ", (await graph.balanceOf(balancerHandler.address)).toString());
        console.log("STEP1 CONTRACT usdc: ", (await usdc.balanceOf(balancerHandler.address)).toString());
        console.log("STEP1 CONTRACT eth: ", (await web3.eth.getBalance(balancerHandler.address)).toString());
        
        console.log("STEP1 USER graph: ", (await graph.balanceOf(governance)).toString());
        console.log("STEP1 USER usdc: ", (await usdc.balanceOf(governance)).toString());
        console.log("STEP1 USER eth: ", (await web3.eth.getBalance(governance)).toString());

        try {
            res = await balancerHandler.performOrder(
                web3.eth.abi.encodeParameter(
                    {
                        "OrderData":{
                            "pool": 'address',
                            "tokenIn": 'address',
                            "tokenOut": 'address',
                            "maxOrderSpend": 'uint256'
                        }
                    },
                    {
                        'pool': pool,
                        'tokenIn': tokenIn,
                        'tokenOut': tokenOut,
                        'maxOrderSpend': '765113153'
                    }
                    ),
                availableToSpend,targetAmount,targetAmountIsSource ,
                 {from: governance} );
        }catch(e){
            console.log(e, res);
        }

        expect(res != null);
        
        console.log('\n');
        console.log("STEP2 CONTRACT graph: ", (await graph.balanceOf(balancerHandler.address)).toString());
        console.log("STEP2 CONTRACT usdc: ", (await usdc.balanceOf(balancerHandler.address)).toString());
        console.log("STEP2 CONTRACT eth: ", (await web3.eth.getBalance(balancerHandler.address)).toString());
        
        console.log("STEP2 USER graph: ", (await graph.balanceOf(governance)).toString());
        console.log("STEP2 USER usdc: ", (await usdc.balanceOf(governance)).toString());
        console.log("STEP2 USER eth: ", (await web3.eth.getBalance(governance)).toString());

 
        await timeMachine.advanceBlock();   //  New Block

        console.log('\n');
        console.log("STEP3 CONTRACT graph: ", (await graph.balanceOf(balancerHandler.address)).toString());
        console.log("STEP3 CONTRACT usdc: ", (await usdc.balanceOf(balancerHandler.address)).toString());
        console.log("STEP3 CONTRACT eth: ", (await web3.eth.getBalance(balancerHandler.address)).toString());
        
        console.log("STEP3 USER graph: ", (await graph.balanceOf(governance)).toString());
        console.log("STEP3 USER usdc: ", (await usdc.balanceOf(governance)).toString());
        console.log("STEP3 USER eth: ", (await web3.eth.getBalance(governance)).toString());


        let events = await balancerHandler.getPastEvents("allEvents", {fromBlock: fromBlock, toBlock: "latest"});
        expect(events != null);
        console.log('\n');
        console.log(events[events.length-1]);

    });

   it('Perform order should working properly with WETH as out', async() => {
        let pool = '0x1050f901a307e7e71471ca3d12dfcea01d0a0a1c';
        let tokenIn = enjin.address;
        let tokenOut = weth.address;

        await enjin.transfer(governance, await enjin.balanceOf(holderEnjin), {from: holderEnjin})
        await enjin.approve(balancerHandler.address, await enjin.balanceOf(governance), {from: governance});        
        
        let availableToSpend = await enjin.balanceOf(governance);
        let targetAmount = 76511315300000;
        let targetAmountIsSource = true;

        console.log("\n****\n");

        console.log("STEP1 CONTRACT weth: ", (await weth.balanceOf(balancerHandler.address)).toString());
        console.log("STEP1 CONTRACT enjin: ", (await enjin.balanceOf(balancerHandler.address)).toString());
        console.log("STEP1 CONTRACT eth: ", (await web3.eth.getBalance(balancerHandler.address)).toString());
        
        console.log("STEP1 USER weth: ", (await weth.balanceOf(governance)).toString());
        console.log("STEP1 USER enjin: ", (await enjin.balanceOf(governance)).toString());
        console.log("STEP1 USER eth: ", (await web3.eth.getBalance(governance)).toString());

        try {
            res = await balancerHandler.performOrder(
                web3.eth.abi.encodeParameter(
                    {
                        "OrderData":{
                            "pool": 'address',
                            "tokenIn": 'address',
                            "tokenOut": 'address',
                            "maxOrderSpend": 'uint256'
                        }
                    },
                    {
                        'pool': pool,
                        'tokenIn': tokenIn,
                        'tokenOut': tokenOut,
                        'maxOrderSpend': '76511315300000'
                    }
                    ),
                availableToSpend,targetAmount,targetAmountIsSource ,
                 {from: governance} );
        }catch(e){
            console.log(e, res);
        }

        expect(res != null);

        console.log("\nSTEP2 CONTRACT weth: ", (await weth.balanceOf(balancerHandler.address)).toString());
        console.log("STEP2 CONTRACT enjin: ", (await enjin.balanceOf(balancerHandler.address)).toString());
        console.log("STEP2 CONTRACT eth: ", (await web3.eth.getBalance(balancerHandler.address)).toString());
        
        console.log("STEP2 USER weth: ", (await weth.balanceOf(governance)).toString());
        console.log("STEP2 USER enjin: ", (await enjin.balanceOf(governance)).toString());
        console.log("STEP2 USER eth: ", (await web3.eth.getBalance(governance)).toString());

        await timeMachine.advanceBlock();

        console.log("\nSTEP3 CONTRACT weth: ", (await weth.balanceOf(balancerHandler.address)).toString());
        console.log("STEP3 CONTRACT enjin: ", (await enjin.balanceOf(balancerHandler.address)).toString());
        console.log("STEP3 CONTRACT eth: ", (await web3.eth.getBalance(balancerHandler.address)).toString());

        console.log("STEP3 USER weth: ", (await weth.balanceOf(governance)).toString());
        console.log("STEP3 USER enjin: ", (await enjin.balanceOf(governance)).toString());
        console.log("STEP3 USER eth: ", (await web3.eth.getBalance(governance)).toString());

        let events = await balancerHandler.getPastEvents("allEvents", {fromBlock: fromBlock, toBlock: "latest"});
        expect(events != null);
        console.log('\n');
        console.log(events[events.length-1]);

    });

    it('Perform order should working properly with WETH as in', async() => {
        let pool = '0x1050f901a307e7e71471ca3d12dfcea01d0a0a1c';
        let tokenOut = enjin.address;
        let tokenIn = weth.address;

        await weth.transfer(governance, await weth.balanceOf(holderWeth), {from: holderWeth})
        await weth.approve(balancerHandler.address, await weth.balanceOf(governance), {from: governance});        
        
        let availableToSpend = 0.15*10**15;
        let targetAmount = 0.15*10**14;
        let targetAmountIsSource = true;

        console.log("\n****\n");

        console.log("STEP1 CONTRACT weth: ", (await weth.balanceOf(balancerHandler.address)).toString());
        console.log("STEP1 CONTRACT enjin: ", (await enjin.balanceOf(balancerHandler.address)).toString());
        console.log("STEP1 CONTRACT eth: ", (await web3.eth.getBalance(balancerHandler.address)).toString());
        
        console.log("STEP1 USER weth: ", (await weth.balanceOf(governance)).toString());
        console.log("STEP1 USER enjin: ", (await enjin.balanceOf(governance)).toString());
        console.log("STEP1 USER eth: ", (await web3.eth.getBalance(governance)).toString());

        try {
            res = await balancerHandler.performOrder(
                web3.eth.abi.encodeParameter(
                    {
                        "OrderData":{
                            "pool": 'address',
                            "tokenIn": 'address',
                            "tokenOut": 'address',
                            "maxOrderSpend": 'uint256'
                        }
                    },
                    {
                        'pool': pool,
                        'tokenIn': tokenIn,
                        'tokenOut': tokenOut,
                        'maxOrderSpend': 0.15*10**14
                    }
                    ),
                availableToSpend,targetAmount,targetAmountIsSource ,
                 {from: governance} );
        }catch(e){
            console.log(e, res);
        }

        expect(res != null);

        console.log("\nSTEP2 CONTRACT weth: ", (await weth.balanceOf(balancerHandler.address)).toString());
        console.log("STEP2 CONTRACT enjin: ", (await enjin.balanceOf(balancerHandler.address)).toString());
        console.log("STEP2 CONTRACT eth: ", (await web3.eth.getBalance(balancerHandler.address)).toString());
        
        console.log("STEP2 USER weth: ", (await weth.balanceOf(governance)).toString());
        console.log("STEP2 USER enjin: ", (await enjin.balanceOf(governance)).toString());
        console.log("STEP2 USER eth: ", (await web3.eth.getBalance(governance)).toString());

        await timeMachine.advanceBlock();

        console.log("\nSTEP3 CONTRACT weth: ", (await weth.balanceOf(balancerHandler.address)).toString());
        console.log("STEP3 CONTRACT enjin: ", (await enjin.balanceOf(balancerHandler.address)).toString());
        console.log("STEP3 CONTRACT eth: ", (await web3.eth.getBalance(balancerHandler.address)).toString());

        console.log("STEP3 USER weth: ", (await weth.balanceOf(governance)).toString());
        console.log("STEP3 USER enjin: ", (await enjin.balanceOf(governance)).toString());
        console.log("STEP3 USER eth: ", (await web3.eth.getBalance(governance)).toString());

        let events = await balancerHandler.getPastEvents("allEvents", {fromBlock: fromBlock, toBlock: "latest"});
        expect(events != null);
        console.log('\n');
        console.log(events[events.length-1]);

    });
});
