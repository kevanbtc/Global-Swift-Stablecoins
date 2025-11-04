// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {ComplianceRegistryUpgradeable} from "../../compliance/ComplianceRegistryUpgradeable.sol";

/// @title Multi-Issuer Bank Network Stablecoin (upgradeable)
/// @notice Multiple banks/issuers mint/burn within quotas and daily caps. Useful for federated networks.
contract MultiIssuerStablecoinUpgradeable is Initializable, UUPSUpgradeable, ERC20Upgradeable, ERC20PermitUpgradeable, AccessControlUpgradeable, PausableUpgradeable {
    bytes32 public constant ADMIN_ROLE   = keccak256("ADMIN_ROLE");
    bytes32 public constant ISSUER_ROLE  = keccak256("ISSUER_ROLE");

    ComplianceRegistryUpgradeable public registry; bytes32 public policyId;

    struct Limits { uint256 quota; uint256 used; uint256 dayCap; uint64 lastDay; uint256 dayUsed; }
    mapping(address => Limits) public limitsOf; // per issuer

    event RegistrySet(address indexed registry);
    event PolicySet(bytes32 indexed policy);
    event LimitsSet(address indexed issuer, uint256 quota, uint256 dayCap);

    function initialize(address admin, string memory name_, string memory symbol_, address registry_, bytes32 policy_) public initializer {
        __ERC20_init(name_, symbol_);
        __ERC20Permit_init(name_);
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin); _grantRole(ADMIN_ROLE, admin);
        registry = ComplianceRegistryUpgradeable(registry_); policyId = policy_;
        emit RegistrySet(registry_); emit PolicySet(policy_);
    }
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function setRegistry(address r) external onlyRole(ADMIN_ROLE){ registry = ComplianceRegistryUpgradeable(r); emit RegistrySet(r);}    
    function setPolicy(bytes32 p) external onlyRole(ADMIN_ROLE){ policyId = p; emit PolicySet(p);}    
    function setLimits(address issuer, uint256 quota, uint256 dayCap) external onlyRole(ADMIN_ROLE){ limitsOf[issuer].quota = quota; limitsOf[issuer].dayCap = dayCap; emit LimitsSet(issuer, quota, dayCap);}    

    function pause() external onlyRole(ADMIN_ROLE){ _pause(); }
    function unpause() external onlyRole(ADMIN_ROLE){ _unpause(); }

    function _rollDay(Limits storage L) internal {
        uint64 d = uint64(block.timestamp / 1 days);
        if (L.lastDay != d) { L.lastDay = d; L.dayUsed = 0; }
    }

    function _checkKYC(address a) internal view { require(registry.canHold(a, policyId), "policy"); }

    function mint(address to, uint256 amount) external onlyRole(ISSUER_ROLE) whenNotPaused {
        _checkKYC(to);
        Limits storage L = limitsOf[msg.sender];
        _rollDay(L);
        require(L.used + amount <= L.quota, "quota");
        require(L.dayUsed + amount <= L.dayCap, "day cap");
        L.used += amount; L.dayUsed += amount;
        _mint(to, amount);
    }
    function burn(address from, uint256 amount) external onlyRole(ISSUER_ROLE) whenNotPaused {
        _checkKYC(from);
        Limits storage L = limitsOf[msg.sender];
        _rollDay(L);
        // burn reduces used quota to allow future minting within total quota window
        if (amount > L.used) { L.used = 0; } else { L.used -= amount; }
        _burn(from, amount);
    }
}
