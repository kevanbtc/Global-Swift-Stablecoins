// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IRiskWeights, IEligibleReserve} from "../interfaces/ExternalInterfaces.sol";

contract BaselCARModule is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant FEED_ROLE  = keccak256("FEED_ROLE");

    IRiskWeights public riskWeights; IEligibleReserve public eligibleReserve; uint256 public liabilitiesUSD18; uint16 public minCARbps;

    event RiskFeedsSet(address riskWeights, address eligibleReserve); event LiabilitiesUpdated(uint256 liab); event MinCARSet(uint16 bps);

    function initialize(address admin, address _risk, address _eligible, uint16 _minCARbps) public initializer {
        __AccessControl_init(); __UUPSUpgradeable_init(); _grantRole(DEFAULT_ADMIN_ROLE, admin); _grantRole(ADMIN_ROLE, admin);
        minCARbps = _minCARbps; riskWeights = IRiskWeights(_risk); eligibleReserve = IEligibleReserve(_eligible);
    }
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function setFeeds(address _risk, address _eligible) external onlyRole(ADMIN_ROLE) { riskWeights = IRiskWeights(_risk); eligibleReserve = IEligibleReserve(_eligible); emit RiskFeedsSet(_risk, _eligible); }
    function setMinCAR(uint16 bps) external onlyRole(ADMIN_ROLE) { minCARbps = bps; emit MinCARSet(bps); }
    function pushLiabilitiesUSD(uint256 liab) external onlyRole(FEED_ROLE) { liabilitiesUSD18 = liab; emit LiabilitiesUpdated(liab); }

    function checkCAR() external view returns (bool ok, uint256 reserves, uint256 required) {
        reserves = eligibleReserve.eligibleValueUSD(); uint16 rw = 10000; uint256 rwa = (liabilitiesUSD18 * rw) / 10000; required = (rwa * minCARbps) / 10000; ok = reserves >= required;
    }
}
