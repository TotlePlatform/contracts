pragma solidity 0.4.25;

import './SafeMath.sol';

contract Affiliate{

  event FeeLog(uint256 ethCollected);

  address public affiliateBeneficiary;
  uint256 public affiliatePercentage; //This is out of 1 ETH, e.g. 0.5 ETH is 50% of the fee

  uint256 public companyPercentage;
  address public companyBeneficiary;

  function init(address _companyBeneficiary, uint256 _companyPercentage, address _affiliateBeneficiary, uint256 _affiliatePercentage) public {
      require(companyBeneficiary == 0x0 && affiliateBeneficiary == 0x0);
      companyBeneficiary = _companyBeneficiary;
      companyPercentage = _companyPercentage;
      affiliateBeneficiary = _affiliateBeneficiary;
      affiliatePercentage = _affiliatePercentage;
  }

  function payout() public {
      // Payout both the affiliate and the company at the same time
      affiliateBeneficiary.transfer(SafeMath.div(SafeMath.mul(address(this).balance, affiliatePercentage), getTotalFeePercentage()));
      companyBeneficiary.transfer(address(this).balance);
  }

  function() public payable {
      emit FeeLog(msg.value);
  }

  function getTotalFeePercentage() public view returns (uint256){
      return affiliatePercentage + companyPercentage;
  }
}
