// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {StableRoles} from "../common/StableRoles.sol";
import {StableErrors} from "../common/StableErrors.sol";
import {ComplianceRegistryUpgradeable} from "../../compliance/ComplianceRegistryUpgradeable.sol";
import {IReserveOracle} from "../../interfaces/ExternalInterfaces.sol";
import {ISO20022Emitter} from "../../utils/ISO20022Emitter.sol";

contract FiatCustodialStablecoinUpgradeable is Initializable, UUPSUpgradeable, ERC20Upgradeable, ERC20PermitUpgradeable, PausableUpgradeable, StableRoles {
    using ISO20022Emitter for *;
    using StableErrors for *;

    ComplianceRegistryUpgradeable public registry;
    bytes32 public policyId;
    IReserveOracle public reserveOracle; // NAV oracle for reserve ratio guard
    uint16 public minReserveRatioBps; // e.g., 10000 = 100%

    event RegistrySet(address indexed registry);
    event PolicySet(bytes32 indexed policyId);
    event OracleSet(address indexed oracle);
    event MinReserveRatioSet(uint16 bps);

    function initialize(
        address admin,
        string memory name_,
        string memory symbol_,
        address registry_,
        bytes32 policyId_,
        address reserveOracle_,
        uint16 minRRBps
    ) public initializer {
        __ERC20_init(name_, symbol_);
        __ERC20Permit_init(name_);
        __Pausable_init();
        __UUPSUpgradeable_init();
        __stableRoles_init(admin);

        registry = ComplianceRegistryUpgradeable(registry_);
        policyId = policyId_;
        reserveOracle = IReserveOracle(reserveOracle_);
        minReserveRatioBps = minRRBps;

        emit RegistrySet(registry_);
        emit PolicySet(policyId_);
        emit OracleSet(reserveOracle_);
        emit MinReserveRatioSet(minRRBps);
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function pause() external onlyRole(ADMIN_ROLE) { _pause(); }
    function unpause() external onlyRole(ADMIN_ROLE) { _unpause(); }

    function setRegistry(address r) external onlyRole(ADMIN_ROLE) { registry = ComplianceRegistryUpgradeable(r); emit RegistrySet(r); }
    function setPolicy(bytes32 p) external onlyRole(ADMIN_ROLE) { policyId = p; emit PolicySet(p); }
    function setOracle(address o) external onlyRole(ADMIN_ROLE) { reserveOracle = IReserveOracle(o); emit OracleSet(o); }
    function setMinReserveRatio(uint16 bps) external onlyRole(ADMIN_ROLE) { minReserveRatioBps = bps; emit MinReserveRatioSet(bps); }

    function _guard(address from, address to) internal view {
        if (paused()) revert StableErrors.Paused();
        if (from != address(0) && to != address(0)) {
            if (!registry.canHold(from, policyId) || !registry.canHold(to, policyId)) revert StableErrors.ComplianceBlocked();
        }
    }

    function _enforceReserveRatio(uint256 newSupply) internal view {
        if (!reserveOracle.isFresh()) revert StableErrors.StaleOracle();
        uint256 nav = reserveOracle.navUSD();
        if (nav * 10000 < newSupply * minReserveRatioBps) revert StableErrors.ReserveRatioBreach();
    }

    function _update(address from, address to, uint256 value) internal override {
        _guard(from, to);
        super._update(from, to, value);
    }

    function mint(address to, uint256 amount, bytes32 pacsHash, string calldata uri, bytes32 lei) external onlyRole(CASHIER_ROLE) {
        _enforceReserveRatio(totalSupply() + amount);
        _mint(to, amount);
        ISO20022Emitter.emitPacs009(pacsHash, uri, uint64(block.number), uint64(block.timestamp), lei);
    }

    function burn(address from, uint256 amount, bytes32 pacsHash, string calldata uri, bytes32 lei) external onlyRole(CASHIER_ROLE) {
        _burn(from, amount);
        ISO20022Emitter.emitPacs009(pacsHash, uri, uint64(block.number), uint64(block.timestamp), lei);
    }
}
