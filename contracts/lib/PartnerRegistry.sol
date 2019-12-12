pragma solidity 0.5.7;

import "./Ownable.sol";
import "./Partner.sol";
import "./Pausable.sol";

contract PartnerRegistry is Ownable, Pausable {

    address target;
    mapping(address => bool) partnerContracts;
    address payable public companyBeneficiary;
    uint256 public basePercentage;
    PartnerRegistry public previousRegistry;

    event PartnerRegistered(address indexed creator, address indexed beneficiary, address partnerContract);

    constructor(PartnerRegistry _previousRegistry, address _target, address payable _companyBeneficiary, uint256 _basePercentage) public {
        previousRegistry = _previousRegistry;
        target = _target;
        companyBeneficiary = _companyBeneficiary;
        basePercentage = _basePercentage;
    }

    function registerPartner(address payable partnerBeneficiary, uint256 partnerPercentage) whenNotPaused external {
        Partner newPartner = Partner(createClone());
        newPartner.init(this,address(0x0000000000000000000000000000000000000000), 0, partnerBeneficiary, partnerPercentage);
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
        newPartner.init(PartnerRegistry(0x0000000000000000000000000000000000000000), _companyBeneficiary, _companyPercentage, partnerBeneficiary, partnerPercentage);
        partnerContracts[address(newPartner)] = true;
        emit PartnerRegistered(address(msg.sender), partnerBeneficiary, address(newPartner));
    }

    function deletePartner(address _partnerAddress) external onlyOwner {
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

    function isValidPartner(address partnerContract) external view returns(bool) {
        return partnerContracts[partnerContract] || previousRegistry.isValidPartner(partnerContract);
    }

    function updateCompanyInfo(address payable newCompanyBeneficiary, uint256 newBasePercentage) external onlyOwner {
        companyBeneficiary = newCompanyBeneficiary;
        basePercentage = newBasePercentage;
    }
}
