// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {ISO20022Emitter} from "../utils/ISO20022Emitter.sol";
import {IReserveOracle, ITravelRule} from "../interfaces/ExternalInterfaces.sol";
import {ComplianceRegistryUpgradeable} from "../compliance/ComplianceRegistryUpgradeable.sol";
import {BaselCARModule} from "../risk/BaselCARModule.sol";

/// @title RebasedBillToken
/// @notice Rebasing, KYC-gated, UUPS-upgradeable bill token with PoR, CAR, ISO 20022 events, and Travel-Rule preclear.
contract RebasedBillToken is
    Initializable, UUPSUpgradeable, ERC20Upgradeable, ERC20PermitUpgradeable,
    AccessControlUpgradeable, PausableUpgradeable
{
    using ISO20022Emitter for *;

    bytes32 public constant ADMIN_ROLE   = keccak256("ADMIN_ROLE");
    bytes32 public constant ORACLE_ROLE  = keccak256("ORACLE_ROLE");
    bytes32 public constant REBASE_ROLE  = keccak256("REBASE_ROLE");
    bytes32 public constant MINT_ROLE    = keccak256("MINT_ROLE");
    bytes32 public constant BURN_ROLE    = keccak256("BURN_ROLE");

    // === Compliance & Risk ===
    ComplianceRegistryUpgradeable public registry;
    bytes32 public activePolicy;
    IReserveOracle public reserveOracle;
    BaselCARModule public carModule;
    ITravelRule public travelRule; // optional

    bool public transfersRestricted;      // enable Travel Rule check
    uint64 public travelRuleTTLSeconds;   // attestation TTL

    // === Rebasing by index (Ampleforth-style shares) ===
    uint256 public index;          // 1e18 scale
    uint256 public constant ONE = 1e18;
    mapping(address => uint256) private _shares; // internal shares
    uint256 private _totalShares;

    // === Guards ===
    uint16 public maxRebaseStepBps;      // e.g., 100 = 1% per rebase
    uint16 public minReserveRatioBps;    // PoR floor against liabilities (technical solvency analogue)

    event PolicyChanged(bytes32 policyId);
    event OracleSet(address reserveOracle);
    event RegistrySet(address registry);
    event CARModuleSet(address car);
    event TravelRuleSet(address tr);
    event TransfersRestricted(bool on, uint64 ttlSec);
    event Rebased(uint256 oldIndex, uint256 newIndex, int256 pctBps);
    event Minted(address indexed to, uint256 shares, uint256 amount);
    event Burned(address indexed from, uint256 shares, uint256 amount);

    // ======== Initializer ========
    function initialize(
        address admin,
        string memory name_,
        string memory symbol_,
        address registry_,
        bytes32 activePolicy_,
        address reserveOracle_,
        address carModule_
    ) public initializer {
        __ERC20_init(name_, symbol_);
        __ERC20Permit_init(name_);
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);

        registry = ComplianceRegistryUpgradeable(registry_);
        activePolicy = activePolicy_;
        reserveOracle = IReserveOracle(reserveOracle_);
        carModule = BaselCARModule(carModule_);

        index = ONE; // 1.0x
        maxRebaseStepBps = 200;     // 2% default
        minReserveRatioBps = 10000; // 100% default

        emit RegistrySet(registry_);
        emit OracleSet(reserveOracle_);
        emit CARModuleSet(carModule_);
        emit PolicyChanged(activePolicy_);
    }

    function _authorizeUpgrade(address newImpl) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    // ======== Views (external API) ========
    function totalSupply() public view override returns (uint256) {
        return (_totalShares * index) / ONE;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return (_shares[account] * index) / ONE;
    }

    // ======== Admin config ========
    function setPolicy(bytes32 pid) public onlyRole(ADMIN_ROLE) {
        activePolicy = pid;
        emit PolicyChanged(pid);
    }

    function setReserveOracle(address o) public onlyRole(ADMIN_ROLE) {
        reserveOracle = IReserveOracle(o);
        emit OracleSet(o);
    }

    function setCARModule(address c) public onlyRole(ADMIN_ROLE) {
        carModule = BaselCARModule(c);
        emit CARModuleSet(c);
    }

    function setTravelRule(address t, bool on, uint64 ttlSec) public onlyRole(ADMIN_ROLE) {
        travelRule = ITravelRule(t);
        transfersRestricted = on;
        travelRuleTTLSeconds = ttlSec;
        emit TravelRuleSet(t);
        emit TransfersRestricted(on, ttlSec);
    }

    function setGuards(uint16 _maxRebaseStepBps, uint16 _minReserveRatioBps) public onlyRole(ADMIN_ROLE) {
        require(_maxRebaseStepBps <= 2000, "rebase step too high");
        maxRebaseStepBps = _maxRebaseStepBps;
        minReserveRatioBps = _minReserveRatioBps;
    }

    function pause() public onlyRole(ADMIN_ROLE) { _pause(); }
    function unpause() public onlyRole(ADMIN_ROLE) { _unpause(); }

    // ======== Core mechanics ========
    function _beforeTokenTransfer(address from, address to, uint256, uint256) internal view {
        require(!paused(), "paused");
        // Mint/Burn allowed to zero/contract; only check end-user transfers
        if (from != address(0) && to != address(0)) {
            require(registry.canHold(from, activePolicy), "from blocked");
            require(registry.canHold(to, activePolicy),   "to blocked");
            if (transfersRestricted && address(travelRule) != address(0)) {
                // NOTE: amount in "external units" needs index; do minimal >0 guard here and rely on front-end to supply `hasPermit` off-chain
                require(travelRule.hasPermit(from, to, 1, travelRuleTTLSeconds), "travel rule");
            }
        }
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        _transferShares(msg.sender, to, _toShares(amount));
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return super.allowance(owner, spender);
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        return super.approve(spender, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transferShares(from, to, _toShares(amount));
        return true;
    }

    // ======== Mint/Burn (roles) ========
    function mint(address to, uint256 amount, bytes32 isoDocHash, string calldata uri, bytes32 lei) public onlyRole(MINT_ROLE) {
        _preSolvencyGuards(amount, true);
        uint256 s = _toShares(amount);
        _totalShares += s;
        _shares[to] += s;

        // Update liabilities in CAR module (if configured)
        _pushLiabilities();

        // ISO 20022 pacs.009 for primary issuance / subscription (hash provided by off-chain doc pipeline)
        ISO20022Emitter.emitPacs009(isoDocHash, uri, uint64(block.number), uint64(block.timestamp), lei);
        emit Minted(to, s, amount);
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount, bytes32 isoDocHash, string calldata uri, bytes32 lei) public onlyRole(BURN_ROLE) {
        uint256 s = _toShares(amount);
        require(_shares[from] >= s, "insufficient");
        _shares[from] -= s;
        _totalShares -= s;

        _pushLiabilities();

        ISO20022Emitter.emitPacs009(isoDocHash, uri, uint64(block.number), uint64(block.timestamp), lei);
        emit Burned(from, s, amount);
        emit Transfer(from, address(0), amount);
    }

    // ======== Rebase (yield distribution) ========
    /// @param pctBps rebase percentage in basis points (e.g., +25 = +0.25% ; -10 = -0.10%)
    function rebase(int256 pctBps, bytes32 stmtHash, string calldata uri) public onlyRole(REBASE_ROLE) {
    require(reserveOracle.isFresh(), "stale PoR");
    int256 step = int256(uint256(maxRebaseStepBps));
    require(pctBps <= step && pctBps >= -step, "step too large");

        uint256 oldIndex = index;
        if (pctBps == 0) {
            ISO20022Emitter.emitCamt053(stmtHash, uri, uint64(block.timestamp));
            emit Rebased(oldIndex, index, pctBps);
            return;
        }

        if (pctBps > 0) {
            uint256 add = (index * uint256(int256(pctBps))) / 10000;
            index = index + add;
        } else {
            uint256 sub = (index * uint256(int256(-pctBps))) / 10000;
            index = index - sub;
        }

        // Post-rebase solvency & CAR
        _postSolvencyGuards();

        ISO20022Emitter.emitCamt053(stmtHash, uri, uint64(block.timestamp));
        emit Rebased(oldIndex, index, pctBps);
    }

    // ======== Internals ========
    function _pushLiabilities() internal {
        if (address(carModule) != address(0)) {
            carModule.pushLiabilitiesUSD(_liabilitiesUSD());
        }
    }

    function _preSolvencyGuards(uint256 amount, bool isMint) internal view {
        require(reserveOracle.isFresh(), "stale PoR");
        // If mint increases liabilities materially, sanity check (best-effort; CAR enforced post-write)
        uint256 afterLiab = _liabilitiesUSD() + (isMint ? amount : 0);
        uint256 nav = reserveOracle.navUSD();
        require(nav * 10000 >= afterLiab * minReserveRatioBps, "reserve ratio");
    }

    function _postSolvencyGuards() internal view {
        require(reserveOracle.isFresh(), "stale PoR");
        uint256 nav = reserveOracle.navUSD();
        uint256 liab = _liabilitiesUSD();
        require(nav * 10000 >= liab * minReserveRatioBps, "reserve ratio");
        if (address(carModule) != address(0)) {
            (bool ok,,) = carModule.checkCAR();
            require(ok, "CAR floor");
        }
    }

    function _liabilitiesUSD() internal view returns (uint256) {
        // Liabilities proxy = totalSupply in external units as USD(18).
        // If your unit != USD, replace with oracle conversion.
        return totalSupply();
    }

    function _toShares(uint256 amount) internal view returns (uint256) {
        // shares = amount / index
        return (amount * ONE) / index;
    }

    function _transferShares(address from, address to, uint256 shares) internal {
        _beforeTokenTransfer(from, to, 0, 0);
        require(_shares[from] >= shares, "balance");
        _shares[from] -= shares;
        _shares[to] += shares;
        emit Transfer(from, to, (shares * index) / ONE);
    }
}
