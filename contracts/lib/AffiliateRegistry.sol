pragma solidity 0.4.25;

import "./Ownable.sol";
import "./Affiliate.sol";

contract AffiliateRegistry is Ownable {

  address target;
  mapping(address => bool) affiliateContracts;
  address public companyBeneficiary;
  uint256 public companyPercentage;

  event AffiliateRegistered(address affiliateContract);


  constructor(address _target, address _companyBeneficiary, uint256 _companyPercentage) public {
     target = _target;
     companyBeneficiary = _companyBeneficiary;
     companyPercentage = _companyPercentage;
  }

  function registerAffiliate(address affiliateBeneficiary, uint256 affiliatePercentage) external {
      Affiliate newAffiliate = Affiliate(createClone());
      newAffiliate.init(companyBeneficiary, companyPercentage, affiliateBeneficiary, affiliatePercentage);
      affiliateContracts[address(newAffiliate)] = true;
      emit AffiliateRegistered(address(newAffiliate));
  }

  function overrideRegisterAffiliate(address _companyBeneficiary, uint256 _companyPercentage, address affiliateBeneficiary, uint256 affiliatePercentage) external onlyOwner {
      Affiliate newAffiliate = Affiliate(createClone());
      newAffiliate.init(_companyBeneficiary, _companyPercentage, affiliateBeneficiary, affiliatePercentage);
      affiliateContracts[address(newAffiliate)] = true;
      emit AffiliateRegistered(address(newAffiliate));
  }

  function deleteAffiliate(address _affiliateAddress) public onlyOwner {
      affiliateContracts[_affiliateAddress] = false;
  }

  function createClone() internal returns (address result) {
      bytes20 targetBytes = bytes20(target);
      assembly {
          let clone := mload(0x40)
          mstore(clone, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
          mstore(add(clone, 0x14), targetBytes)
          mstore(add(clone, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
          result := create(0, clone, 0x37)
      }
  }

  function isValidAffiliate(address affiliateContract) public view returns(bool) {
      return affiliateContracts[affiliateContract];
  }

  function updateCompanyInfo(address newCompanyBeneficiary, uint256 newCompanyPercentage) public onlyOwner {
      companyBeneficiary = newCompanyBeneficiary;
      companyPercentage = newCompanyPercentage;
  }
}
