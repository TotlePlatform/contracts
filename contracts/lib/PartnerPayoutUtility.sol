pragma solidity 0.5.7;

import './ERC20.sol';

contract PartnerV1 {
    function payout(address[] calldata tokens, uint256[] calldata amounts) external;
}

contract PartnerV2 {
    function payout(address[] calldata tokens) external;
}

contract PartnerPayoutUtility {

    bytes32 constant V1_CODE_HASH = 0x70ed410f7794fe6186298c7d9ecaebe39b45c76ec8e972fae082b8708e281f89;
    function payout(address partnerAddress, address[] memory tokens) public {
        bytes32 codeHash;
        assembly {
            codeHash := extcodehash(partnerAddress)
        }
        
        if (codeHash == V1_CODE_HASH){
            PartnerV1 partner = PartnerV1(partnerAddress);
            uint256[] memory amounts = new uint256[](tokens.length);
            for(uint256 index = 0; index<amounts.length; index++){
                if(tokens[index]== address(0x0000000000000000000000000000000000000000)){
                    amounts[index] = partnerAddress.balance;
                } else {
                    ERC20 token = ERC20(tokens[index]);
                    amounts[index] = token.balanceOf(partnerAddress);
                }
            }
            partner.payout(tokens, amounts);
        } else {
            // All partner contracts after V1 have the same ABI, so additional codeHash checks aren't required
            PartnerV2 partner = PartnerV2(partnerAddress);
            partner.payout(tokens);
        }
    } 
}