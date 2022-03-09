// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./Utils.sol";
import "./PartnerRegistry.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Partner is ReentrancyGuard {
    address payable public partnerBeneficiary;
    uint256 public partnerPercentage; //This is out of 1 ETH, e.g. 0.5 ETH is 50% of the fee

    uint256 public overrideCompanyPercentage;
    address payable public overrideCompanyBeneficiary;

    PartnerRegistry public registry;

    event LogPayout(address[] tokens, uint256[] amount);

    function init(
        PartnerRegistry _registry,
        address payable _overrideCompanyBeneficiary,
        uint256 _overrideCompanyPercentage,
        address payable _partnerBeneficiary,
        uint256 _partnerPercentage
    ) public {
        require(
            registry ==
                PartnerRegistry(0x0000000000000000000000000000000000000000) &&
                overrideCompanyBeneficiary == address(0x0) &&
                partnerBeneficiary == address(0x0)
        );
        overrideCompanyBeneficiary = _overrideCompanyBeneficiary;
        overrideCompanyPercentage = _overrideCompanyPercentage;
        partnerBeneficiary = _partnerBeneficiary;
        partnerPercentage = _partnerPercentage;
        overrideCompanyPercentage = _overrideCompanyPercentage;
        registry = _registry;
    }

    function payout(address[] memory tokens) public nonReentrant {
        uint256 totalFeePercentage = getTotalFeePercentage();
        address payable _companyBeneficiary = companyBeneficiary();
        uint256[] memory amountsPaidOut = new uint256[](tokens.length);
        // Payout both the partner and the company at the same time
        for (uint256 index = 0; index < tokens.length; index++) {
            uint256 balance = tokens[index] == Utils.eth_address()
                ? address(this).balance
                : IERC20(tokens[index]).balanceOf(address(this));
            amountsPaidOut[index] = balance;
            uint256 partnerAmount = SafeMath.div(
                SafeMath.mul(balance, partnerPercentage),
                totalFeePercentage
            );
            uint256 companyAmount = balance - partnerAmount;
            if (tokens[index] == Utils.eth_address()) {
                bool success;
                (success,) = partnerBeneficiary.call{value: partnerAmount, gas: 5000}("");
                require(success,"Transfer failed");
                (success,) =_companyBeneficiary.call{value: companyAmount, gas: 5000}("");
                require(success,"Transfer failed");

            } else {
                SafeERC20.safeTransfer(
                    IERC20(tokens[index]),
                    partnerBeneficiary,
                    partnerAmount
                );
                SafeERC20.safeTransfer(
                    IERC20(tokens[index]),
                    _companyBeneficiary,
                    companyAmount
                );
            }
        }
        emit LogPayout(tokens, amountsPaidOut);
    }

    function getTotalFeePercentage() public view returns (uint256) {
        return partnerPercentage + companyPercentage();
    }

    function companyPercentage() public view returns (uint256) {
        if (
            registry !=
            PartnerRegistry(0x0000000000000000000000000000000000000000)
        ) {
            return Math.max(registry.basePercentage(), partnerPercentage);
        } else {
            return overrideCompanyPercentage;
        }
    }

    function companyBeneficiary() public view returns (address payable) {
        if (
            registry !=
            PartnerRegistry(0x0000000000000000000000000000000000000000)
        ) {
            return registry.companyBeneficiary();
        } else {
            return overrideCompanyBeneficiary;
        }
    }

    receive() external payable {}
}
