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

contract RebasedBillToken is Initializable, UUPSUpgradeable, ERC20Upgradeable, ERC20PermitUpgradeable, AccessControlUpgradeable, PausableUpgradeable {
    using ISO20022Emitter for *;
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant REBASE_ROLE = keccak256("REBASE_ROLE");
    bytes32 public constant MINT_ROLE = keccak256("MINT_ROLE");
    bytes32 public constant BURN_ROLE = keccak256("BURN_ROLE");

    ComplianceRegistryUpgradeable public registry; bytes32 public activePolicy; IReserveOracle public reserveOracle; BaselCARModule public carModule; ITravelRule public travelRule;
    bool public transfersRestricted; uint64 public travelRuleTTLSeconds;

    uint256 public index; uint256 public constant ONE = 1e18; mapping(address => uint256) private _shares; uint256 private _totalShares;
    uint16 public maxRebaseStepBps; uint16 public minReserveRatioBps;

    event PolicyChanged(bytes32 policyId); event OracleSet(address reserveOracle); event RegistrySet(address registry); event CARModuleSet(address car); event TravelRuleSet(address tr); event TransfersRestricted(bool on, uint64 ttlSec); event Rebased(uint256 oldIndex, uint256 newIndex, int256 pctBps); event Minted(address indexed to, uint256 shares, uint256 amount); event Burned(address indexed from, uint256 shares, uint256 amount);

    function initialize(address admin, string memory name_, string memory symbol_, address registry_, bytes32 activePolicy_, address reserveOracle_, address carModule_) public initializer {
        __ERC20_init(name_, symbol_); __ERC20Permit_init(name_); __AccessControl_init(); __Pausable_init(); __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin); _grantRole(ADMIN_ROLE, admin);
        registry = ComplianceRegistryUpgradeable(registry_); activePolicy = activePolicy_; reserveOracle = IReserveOracle(reserveOracle_); carModule = BaselCARModule(carModule_);
        index = ONE; maxRebaseStepBps = 200; minReserveRatioBps = 10000;
        emit RegistrySet(registry_); emit OracleSet(reserveOracle_); emit CARModuleSet(carModule_); emit PolicyChanged(activePolicy_);
    }
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function totalSupply() public view override returns (uint256) { return (_totalShares * index) / ONE; }
    function balanceOf(address a) public view override returns (uint256) { return (_shares[a] * index) / ONE; }

    function setPolicy(bytes32 pid) external onlyRole(ADMIN_ROLE) { activePolicy = pid; emit PolicyChanged(pid); }
    function setReserveOracle(address o) external onlyRole(ADMIN_ROLE) { reserveOracle = IReserveOracle(o); emit OracleSet(o); }
    function setCARModule(address c) external onlyRole(ADMIN_ROLE) { carModule = BaselCARModule(c); emit CARModuleSet(c); }
    function setTravelRule(address t, bool on, uint64 ttlSec) external onlyRole(ADMIN_ROLE) { travelRule = ITravelRule(t); transfersRestricted = on; travelRuleTTLSeconds = ttlSec; emit TravelRuleSet(t); emit TransfersRestricted(on, ttlSec); }
    function setGuards(uint16 _max, uint16 _minRR) external onlyRole(ADMIN_ROLE) { require(_max <= 2000, "rebase step too high"); maxRebaseStepBps = _max; minReserveRatioBps = _minRR; }
    function pause() external onlyRole(ADMIN_ROLE) { _pause(); } function unpause() external onlyRole(ADMIN_ROLE) { _unpause(); }

    // local guard function (not overriding OZ v5 hooks)
    function _beforeTokenTransfer(address from, address to, uint256, uint256) internal view {
        require(!paused(), "paused"); if (from != address(0) && to != address(0)) {
            require(registry.canHold(from, activePolicy), "from blocked"); require(registry.canHold(to, activePolicy), "to blocked");
            if (transfersRestricted && address(travelRule) != address(0)) { require(travelRule.hasPermit(from, to, 1, travelRuleTTLSeconds), "travel rule"); }
        }
    }
    function transfer(address to, uint256 amount) public override returns (bool) { _transferShares(msg.sender, to, _toShares(amount)); return true; }
    function approve(address s, uint256 a) public override returns (bool) { return super.approve(s, a); }
    function transferFrom(address f, address t, uint256 a) public override returns (bool) { _spendAllowance(f, msg.sender, a); _transferShares(f, t, _toShares(a)); return true; }

    function mint(address to, uint256 amount, bytes32 hash, string calldata uri, bytes32 lei) external onlyRole(MINT_ROLE) {
        _preSolvencyGuards(amount, true); uint256 s = _toShares(amount); _totalShares += s; _shares[to] += s; _pushLiabilities(); ISO20022Emitter.emitPacs009(hash, uri, uint64(block.number), uint64(block.timestamp), lei); emit Minted(to, s, amount); emit Transfer(address(0), to, amount);
    }
    function burn(address from, uint256 amount, bytes32 hash, string calldata uri, bytes32 lei) external onlyRole(BURN_ROLE) {
        uint256 s = _toShares(amount); require(_shares[from] >= s, "insufficient"); _shares[from] -= s; _totalShares -= s; _pushLiabilities(); ISO20022Emitter.emitPacs009(hash, uri, uint64(block.number), uint64(block.timestamp), lei); emit Burned(from, s, amount); emit Transfer(from, address(0), amount);
    }

    function rebase(int256 pctBps, bytes32 stmtHash, string calldata uri) external onlyRole(REBASE_ROLE) {
        require(reserveOracle.isFresh(), "stale PoR"); require(pctBps <= int256(uint256(maxRebaseStepBps)) && pctBps >= -int256(uint256(maxRebaseStepBps)), "step too large");
        uint256 old = index; if (pctBps != 0) { if (pctBps > 0) { index = index + (index * uint256(int256(pctBps)))/10000; } else { index = index - (index * uint256(int256(-pctBps)))/10000; } _postSolvencyGuards(); }
        ISO20022Emitter.emitCamt053(stmtHash, uri, uint64(block.timestamp)); emit Rebased(old, index, pctBps);
    }

    function _pushLiabilities() internal { if (address(carModule) != address(0)) { carModule.pushLiabilitiesUSD(_liabilitiesUSD()); } }
    function _preSolvencyGuards(uint256 amount, bool isMint) internal view { require(reserveOracle.isFresh(), "stale PoR"); uint256 afterLiab = _liabilitiesUSD() + (isMint ? amount : 0); uint256 nav = reserveOracle.navUSD(); require(nav * 10000 >= afterLiab * minReserveRatioBps, "reserve ratio"); }
    function _postSolvencyGuards() internal view { require(reserveOracle.isFresh(), "stale PoR"); uint256 nav = reserveOracle.navUSD(); uint256 liab = _liabilitiesUSD(); require(nav * 10000 >= liab * minReserveRatioBps, "reserve ratio"); if (address(carModule) != address(0)) { (bool ok,,) = carModule.checkCAR(); require(ok, "CAR floor"); } }
    function _liabilitiesUSD() internal view returns (uint256) { return totalSupply(); }
    function _toShares(uint256 amount) internal view returns (uint256) { return (amount * ONE) / index; }
    function _transferShares(address f, address t, uint256 s) internal { _beforeTokenTransfer(f, t, 0, 0); require(_shares[f] >= s, "balance"); _shares[f] -= s; _shares[t] += s; emit Transfer(f, t, (s * index) / ONE); }
}
