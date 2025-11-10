// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {Roles} from "../common/Roles.sol";
import {PolicyGuard} from "../policy/PolicyGuard.sol";
import {AttestationRegistry} from "../attest/AttestationRegistry.sol";
import {ReserveVault} from "../reserves/ReserveVault.sol";

/**
 * @title StableUSD
 * @notice Upgradeable, policy-gated ERC20 with mint/burn controlled by roles and reserve attestation freshness.
 * @dev This is NOT legal compliance. It enforces your policy tech knobs.
 */
contract StableUSD is Initializable, ERC20Upgradeable, ERC20PermitUpgradeable, UUPSUpgradeable, PausableUpgradeable, AccessControlUpgradeable {
    PolicyGuard public guard;
    AttestationRegistry public attest;
    ReserveVault public reserve;

    // op codes
    bytes32 public constant OP_MINT       = keccak256("MINT");
    bytes32 public constant OP_REDEEM     = keccak256("REDEEM");
    bytes32 public constant OP_NAV_ATTEST = keccak256("NAV_ATTEST");

    // last attestation time cached for quick policy checks
    uint64 public lastAttAsOf;

    event Bound(address guard, address attest, address reserve);
    event Minted(address indexed to, uint256 amount, address indexed by);
    event Burned(address indexed from, uint256 amount, address indexed by);
    event AttestationAnchored(uint256 indexed id, uint64 asOf);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    function initialize(
        address governor,
        address guardian,
        string memory name_,
        string memory symbol_
    ) public initializer {
        __ERC20_init(name_, symbol_);
        __ERC20Permit_init(name_);
        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(Roles.GOVERNOR, governor);
        _grantRole(Roles.GUARDIAN, guardian);
        _grantRole(Roles.MINTER, governor);
        _grantRole(Roles.BURNER, governor);
        _grantRole(Roles.UPGRADER, governor);
    }

    function _authorizeUpgrade(address) internal override onlyRole(Roles.UPGRADER) {}

    function bind(address guard_, address attest_, address reserve_) public onlyRole(Roles.GOVERNOR) {
        guard = PolicyGuard(guard_);
        attest = AttestationRegistry(attest_);
        reserve = ReserveVault(reserve_);
        emit Bound(guard_, attest_, reserve_);
    }

    function pause() public onlyRole(Roles.GUARDIAN) { _pause(); }
    function unpause() public onlyRole(Roles.GUARDIAN) { _unpause(); }

    // --- mint/burn ---

    function mint(address to, uint256 amount, bytes32 country) public onlyRole(Roles.MINTER) whenNotPaused {
        // Check policy: freshness & allocations (you can wire live allocation calc off-chain; here we only do freshness)
        (uint256 id, AttestationRegistry.Attestation memory a) = attest.latest();
        require(id != 0, "no_attestation");
        uint256 age = block.timestamp > a.asOf ? (block.timestamp - a.asOf) : 0;
        (bool ok, ) = guard.check(OP_MINT, country, age, 0, 0, PolicyGuard.AssetClass.CASH);
        require(ok, "policy_denied");

        _mint(to, amount);
        emit Minted(to, amount, msg.sender);
        lastAttAsOf = a.asOf;
    }

    function burn(address from, uint256 amount, bytes32 country) public onlyRole(Roles.BURNER) whenNotPaused {
        (bool ok,) = guard.check(OP_REDEEM, country, 0, 0, 0, PolicyGuard.AssetClass.CASH);
        require(ok, "policy_denied");
        _burn(from, amount);
        emit Burned(from, amount, msg.sender);
    }

    // optional: record explicit anchoring of an attestation id (ops workflow)
    function anchorAttestation(uint256 id) public onlyRole(Roles.AUDITOR) {
        (, AttestationRegistry.Attestation memory a) = attest.latest();
        require(a.asOf != 0, "no_att");
        lastAttAsOf = a.asOf;
        emit AttestationAnchored(id, a.asOf);
    }

    // ERC20 v5 hook
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable)
        whenNotPaused
    {
        super._update(from, to, value);
        // (optionally enforce kycApproved[to] via guard if you connect user-level data here)
    }
}
