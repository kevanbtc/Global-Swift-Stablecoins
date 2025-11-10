// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC20PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {Types} from "../common/Types.sol";
import {CustomErrors} from "../common/Errors.sol";

interface IPolicyEngine {
    function checkTransfer(Types.TransferContext calldata ctx) external view;
}

contract InstitutionalEMTUpgradeable is
    Initializable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    ERC20PausableUpgradeable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    bytes32 public constant GOVERNOR_ROLE   = keccak256("GOVERNOR_ROLE");
    bytes32 public constant MINTER_ROLE     = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE     = keccak256("PAUSER_ROLE");
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE"); // ERC-1644

    IPolicyEngine public policy;

    // Optional per-account caps tracking (consulted by PolicyEngine)
    mapping(address => uint256) public dailySpent;
    mapping(address => uint256) public dailyWindow; // day id

    // --- Init / Upgrade ---

    function initialize(
        address admin,
        address governor,
        string memory name_,
        string memory symbol_,
        address policy_
    ) public initializer {
        __ERC20_init(name_, symbol_);
        __ERC20Permit_init(name_);
        __ERC20Pausable_init();
        __UUPSUpgradeable_init();
    __AccessControl_init();
    _grantRole(DEFAULT_ADMIN_ROLE, admin);
        __ReentrancyGuard_init();

        _grantRole(GOVERNOR_ROLE, governor);
        _grantRole(PAUSER_ROLE, governor);
        policy = IPolicyEngine(policy_);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(GOVERNOR_ROLE) {
        // Optional: add code hash allowlist / time delay via governance
    }

    // --- Admin controls ---

    function setPolicy(address policy_) public onlyRole(GOVERNOR_ROLE) {
        policy = IPolicyEngine(policy_);
    }

    function pause() public onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() public onlyRole(PAUSER_ROLE) { _unpause(); }
    // Snapshot feature removed in this build due to OZ v5 package layout; can be re-enabled with a local snapshot mixin

    // --- Mint/Redeem (issuance ops) ---

    function mint(address to, uint256 amt) public onlyRole(MINTER_ROLE) nonReentrant {
        _mint(to, amt);
    }

    function redeem(uint256 amt) public nonReentrant {
        _burn(msg.sender, amt);
        // off-chain settlement wiring goes here (hook/event)
    }

    // --- ERC-1644 hooks (called by external controller that holds CONTROLLER_ROLE on this token) ---

    function controllerTransfer(address from, address to, uint256 value, bytes calldata /*data*/) public onlyRole(CONTROLLER_ROLE)
    {
        _update(from, to, value);
    }

    function controllerRedeem(address from, uint256 value, bytes calldata /*data*/) public onlyRole(CONTROLLER_ROLE)
    {
        _burn(from, value);
    }

    // --- Transfer gating & caps ---

    function _update(address from, address to, uint256 value)
        internal
    override(ERC20Upgradeable, ERC20PausableUpgradeable)
    {
        if (address(policy) != address(0) && from != address(0) && to != address(0)) {
            Types.TransferContext memory ctx = Types.TransferContext({
                token: address(this),
                operator: msg.sender,
                from: from,
                to: to,
                amount: value
            });
            policy.checkTransfer(ctx);
        }

        // Optional daily-outflow limiter (reads policy flags if you want tight coupling)
        if (from != address(0)) {
            uint256 day = block.timestamp / 1 days;
            if (dailyWindow[from] != day) {
                dailyWindow[from] = day;
                dailySpent[from] = 0;
            }
            // Example cap: 0 means off. If enforced by PolicyEngine, it can read these via view.
        }
        super._update(from, to, value);
    }

    // _beforeTokenTransfer removed in OZ v5 (handled in _update)

    // AccessControlUpgradeable already implements supportsInterface via ERC165
}
