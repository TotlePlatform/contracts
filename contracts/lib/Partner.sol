pragma solidity 0.5.7;

import './SafeMath.sol';
import './ERC20.sol';
import './ERC20SafeTransfer.sol';
import './Utils.sol';
import './PartnerRegistry.sol';
import './Math.sol';
contract Partner {

    address payable public partnerBeneficiary;
    uint256 public partnerPercentage; //This is out of 1 ETH, e.g. 0.5 ETH is 50% of the fee

    uint256 public overrideCompanyPercentage;
    address payable public overrideCompanyBeneficiary;

    PartnerRegistry public registry;

    event LogPayout(
        address[] tokens,
        uint256[] amount
    );

    function init(
        PartnerRegistry _registry,
        address payable _overrideCompanyBeneficiary,
        uint256 _overrideCompanyPercentage,
        address payable _partnerBeneficiary,
        uint256 _partnerPercentage
    ) public {
        require(registry == PartnerRegistry(0x0000000000000000000000000000000000000000) &&
          overrideCompanyBeneficiary == address(0x0) && partnerBeneficiary == address(0x0)
        );
        overrideCompanyBeneficiary = _overrideCompanyBeneficiary;
        overrideCompanyPercentage = _overrideCompanyPercentage;
        partnerBeneficiary = _partnerBeneficiary;
        partnerPercentage = _partnerPercentage;
        overrideCompanyPercentage = _overrideCompanyPercentage;
        registry = _registry;
    }

    function payout(
        address[] memory tokens
    ) public {
        uint totalFeePercentage = getTotalFeePercentage();
        address payable companyBeneficiary = companyBeneficiary();
        uint256[] memory amountsPaidOut = new uint256[](tokens.length);
        // Payout both the partner and the company at the same time
        for(uint256 index = 0; index<tokens.length; index++){
            uint256 balance = tokens[index] == Utils.eth_address() ? address(this).balance : ERC20(tokens[index]).balanceOf(address(this));
            amountsPaidOut[index] = balance;
            uint256 partnerAmount = SafeMath.div(SafeMath.mul(balance, partnerPercentage), getTotalFeePercentage());
            uint256 companyAmount = balance - partnerAmount;
            if(tokens[index] == Utils.eth_address()){
                partnerBeneficiary.transfer(partnerAmount);
                companyBeneficiary.transfer(companyAmount);
            } else {
                ERC20SafeTransfer.safeTransfer(tokens[index], partnerBeneficiary, partnerAmount);
                ERC20SafeTransfer.safeTransfer(tokens[index], companyBeneficiary, companyAmount);
            }
        }
	    emit LogPayout(tokens,amountsPaidOut);
    }

    function getTotalFeePercentage() public view returns (uint256){
        return partnerPercentage + companyPercentage();
    }

    function companyPercentage() public view returns (uint256){
        if(registry != PartnerRegistry(0x0000000000000000000000000000000000000000)){
            return Math.max(registry.basePercentage(), partnerPercentage);
        } else {
            return overrideCompanyPercentage;
        }
    }

    function companyBeneficiary() public view returns (address payable) {
        if(registry != PartnerRegistry(0x0000000000000000000000000000000000000000)){
            return registry.companyBeneficiary();
        } else {
            return overrideCompanyBeneficiary;
        }    
    }

    function() external payable {

    }
}
