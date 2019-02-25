pragma solidity 0.4.25;
pragma experimental ABIEncoderV2;

import "./TotlePrimary.sol";
import "./lib/TokenTransferProxy.sol";
import "./lib/Ownable.sol";
import "./lib/ERC20.sol";
import "./lib/AllowanceSetter.sol";

contract TotleProxyPrimary is Ownable, AllowanceSetter {

    TokenTransferProxy public tokenTransferProxy;
    TotlePrimary public totlePrimary;

    constructor(address _tokenTransferProxy, address _totlePrimary) public {
        tokenTransferProxy = TokenTransferProxy(_tokenTransferProxy);
        totlePrimary = TotlePrimary(_totlePrimary);
    }

    function performRebalance(
        TotlePrimary.Trade[] memory trades,
        address feeAccount,
        bytes32 id,
        address paymentReceiver,
        bool redirectEth,
        address[] redirectTokens
    )
        public
        payable
    {
          transferTokensIn(trades);
          totlePrimary.performRebalance.value(msg.value)(trades, feeAccount, id);
          transferTokensOut(trades, paymentReceiver, redirectTokens);
          if(redirectEth) {
              paymentReceiver.transfer(address(this).balance);
          } else {
              msg.sender.transfer(address(this).balance);
          }
    }

    function transferTokensIn(TotlePrimary.Trade[] trades) internal {
        for (uint256 i = 0; i < trades.length; i++) {
            if (trades[i].isSell) {
                if (!tokenTransferProxy.transferFrom(
                        trades[i].tokenAddress,
                        msg.sender,
                        address(this),
                        trades[i].tokenAmount
                )) {
                    revert("TTP unable to transfer tokens to proxy");
                }
                approveAddress(address(tokenTransferProxy), trades[i].tokenAddress);
           }
        }
    }

    function transferTokensOut(TotlePrimary.Trade[] trades, address receiver, address[] redirectTokens) internal {
        for (uint256 i = 0; i < trades.length; i++) {
            bool redirect = false;
            for(uint256 tokenIndex = 0; tokenIndex < redirectTokens.length; tokenIndex++){
                if(redirectTokens[tokenIndex] == trades[i].tokenAddress){
                    redirect = true;
                    break;
                }
            }
            uint256 balance = ERC20(trades[i].tokenAddress).balanceOf(address(this));
            if(balance > 0){
                ERC20SafeTransfer.safeTransfer(trades[i].tokenAddress, redirect ? receiver : msg.sender, balance);
            }
        }
    }

    function setTokenTransferProxy(address _newTokenTransferProxy) public onlyOwner {
        tokenTransferProxy = TokenTransferProxy(_newTokenTransferProxy);
    }

    function setTotlePrimary(address _newTotlePrimary) public onlyOwner {
        totlePrimary = TotlePrimary(_newTotlePrimary);
    }

    function() public payable{}
}
