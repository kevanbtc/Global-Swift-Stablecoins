// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

// Minimal upgradeable court order registry for gating policy
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract CourtOrderRegistryUpgradeable is Initializable, UUPSUpgradeable, AccessControlUpgradeable {
	bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

	mapping(bytes32 => bool) public activeOrder;     // orderId => active
	mapping(address => bool) public tokenGlobalFreeze; // token => frozen

	event OrderSet(bytes32 indexed id, bool active);
	event GlobalFreezeSet(address indexed token, bool frozen);

	function initialize(address admin, address governor) public initializer {
		__AccessControl_init();
		__UUPSUpgradeable_init();
		_grantRole(DEFAULT_ADMIN_ROLE, admin);
		_grantRole(GOVERNOR_ROLE, governor);
	}

	function _authorizeUpgrade(address) internal override onlyRole(GOVERNOR_ROLE) {}

	function setOrder(bytes32 id, bool on) public onlyRole(GOVERNOR_ROLE) {
		activeOrder[id] = on;
		emit OrderSet(id, on);
	}

	function setGlobalFreeze(address token, bool on) public onlyRole(GOVERNOR_ROLE) {
		tokenGlobalFreeze[token] = on;
		emit GlobalFreezeSet(token, on);
	}

	// Interfaces consumed by PolicyEngine
	function globalFreeze(address token) public view returns (bool) {
		return tokenGlobalFreeze[token];
	}

	function isActive(bytes32 orderId) public view returns (bool) {
		return activeOrder[orderId];
	}
}
