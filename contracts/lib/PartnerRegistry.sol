// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./Partner.sol";

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PartnerRegistry is Ownable, Pausable {
    address target;
    mapping(address => bool) partnerContracts;
    address payable public companyBeneficiary;
    uint256 public basePercentage;
    PartnerRegistry public previousRegistry;

    event PartnerRegistered(
        address indexed creator,
        address indexed beneficiary,
        address partnerContract
    );

    constructor(
        PartnerRegistry _previousRegistry,
        address _target,
        address payable _companyBeneficiary,
        uint256 _basePercentage
    ) {
        previousRegistry = _previousRegistry;
        target = _target;
        companyBeneficiary = _companyBeneficiary;
        basePercentage = _basePercentage;
    }

    /*
     * Public functions
     */

    /// @dev registers a partner and deploys a partner contract
    /// @param partnerBeneficiary The address that the partner will receive payments to - NON-CHANGEABLE
    /// @param partnerPercentage The percentage fee the partner wants to take - this is out of 1**18, so 1**16 would be 1% fee
    function registerPartner(
        address payable partnerBeneficiary,
        uint256 partnerPercentage
    ) external whenNotPaused {
        Partner newPartner = Partner(createClone());
        newPartner.init(
            this,
            payable(0x0),
            0,
            partnerBeneficiary,
            partnerPercentage
        );
        partnerContracts[address(newPartner)] = true;
        emit PartnerRegistered(
            address(msg.sender),
            partnerBeneficiary,
            address(newPartner)
        );
    }

    /// @dev registers a partner and deploys a partner contract with custom company values, only usable by owner
    /// @param _companyBeneficiary The address that the company will receive payments to - NON-CHANGEABLE
    /// @param _companyPercentage The percentage fee the company wants to take - this is out of 1**18, so 1**16 would be 1% fee
    /// @param partnerBeneficiary The address that the partner will receive payments to - NON-CHANGEABLE
    /// @param partnerPercentage The percentage fee the partner wants to take - this is out of 1**18, so 1**16 would be 1% fee
    function overrideRegisterPartner(
        address payable _companyBeneficiary,
        uint256 _companyPercentage,
        address payable partnerBeneficiary,
        uint256 partnerPercentage
    ) external onlyOwner {
        Partner newPartner = Partner(createClone());
        newPartner.init(
            PartnerRegistry(0x0000000000000000000000000000000000000000),
            _companyBeneficiary,
            _companyPercentage,
            partnerBeneficiary,
            partnerPercentage
        );
        partnerContracts[address(newPartner)] = true;
        emit PartnerRegistered(
            address(msg.sender),
            partnerBeneficiary,
            address(newPartner)
        );
    }

    /// @dev Marks a partner contract as no longer valid
    /// @param partnerContract The partner contract address to disable
    function deletePartner(address partnerContract) external onlyOwner {
        partnerContracts[partnerContract] = false;
    }

    /*
     * Internal functions
     */

    /// @dev Creates a clone of contract - from EIP-1167
    /// @param result The address of the contract that was created
    function createClone() internal returns (address payable result) {
        bytes20 targetBytes = bytes20(target);
        assembly {
            let clone := mload(0x40)
            mstore(
                clone,
                0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000
            )
            mstore(add(clone, 0x14), targetBytes)
            mstore(
                add(clone, 0x28),
                0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000
            )
            result := create(0, clone, 0x37)
        }
    }
    /// @dev Used to tell whether a given address is a valid partner contract, i.e. it was created on this contract or a historic registry, and it hasn't been disabled
    /// @param partnerContract The partner contract address to validate

    function isValidPartner(address partnerContract)
        external
        view
        returns (bool)
    {
        return
            partnerContracts[partnerContract] ||
            previousRegistry.isValidPartner(partnerContract);
    }

    /// @dev Updates the beneficiary and default percentage for the company
    /// @param newCompanyBeneficiary New beneficiary address for company
    /// @param newBasePercentage New base percentage for company
    function updateCompanyInfo(
        address payable newCompanyBeneficiary,
        uint256 newBasePercentage
    ) external onlyOwner {
        companyBeneficiary = newCompanyBeneficiary;
        basePercentage = newBasePercentage;
    }
}
