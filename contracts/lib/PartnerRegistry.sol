pragma solidity 0.5.7;

import "./Ownable.sol";
import "./Partner.sol";

contract PartnerRegistry is Ownable {

    address target;
    mapping(address => bool) partnerContracts;
    address payable public companyBeneficiary;
    uint256 public companyPercentage;

    event PartnerRegistered(address indexed creator, address indexed beneficiary, address partnerContract);


    constructor(address _target, address payable _companyBeneficiary, uint256 _companyPercentage) public {
        target = _target;
        companyBeneficiary = _companyBeneficiary;
        companyPercentage = _companyPercentage;
    }

    function registerPartner(address payable partnerBeneficiary, uint256 partnerPercentage) external {
        Partner newPartner = Partner(createClone());
        newPartner.init(companyBeneficiary, companyPercentage, partnerBeneficiary, partnerPercentage);
        partnerContracts[address(newPartner)] = true;
        emit PartnerRegistered(address(msg.sender), partnerBeneficiary, address(newPartner));
    }

    function overrideRegisterPartner(
        address payable _companyBeneficiary,
        uint256 _companyPercentage,
        address payable partnerBeneficiary,
        uint256 partnerPercentage
    ) external onlyOwner {
        Partner newPartner = Partner(createClone());
        newPartner.init(_companyBeneficiary, _companyPercentage, partnerBeneficiary, partnerPercentage);
        partnerContracts[address(newPartner)] = true;
        emit PartnerRegistered(address(msg.sender), partnerBeneficiary, address(newPartner));
    }

    function deletePartner(address _partnerAddress) public onlyOwner {
        partnerContracts[_partnerAddress] = false;
    }

    function createClone() internal returns (address payable result) {
        bytes20 targetBytes = bytes20(target);
        assembly {
            let clone := mload(0x40)
            mstore(clone, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(clone, 0x14), targetBytes)
            mstore(add(clone, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            result := create(0, clone, 0x37)
        }
    }

    function isValidPartner(address partnerContract) public view returns(bool) {
        return partnerContracts[partnerContract];
    }

    function updateCompanyInfo(address payable newCompanyBeneficiary, uint256 newCompanyPercentage) public onlyOwner {
        companyBeneficiary = newCompanyBeneficiary;
        companyPercentage = newCompanyPercentage;
    }
}
