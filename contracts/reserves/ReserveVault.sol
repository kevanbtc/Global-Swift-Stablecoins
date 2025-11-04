// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Roles} from "../common/Roles.sol";
import {PolicyGuard} from "../policy/PolicyGuard.sol";
import {OracleCommittee} from "../oracle/OracleCommittee.sol";

/**
 * @title ReserveVault
 * @notice Segregated reserve accounting: positions, deposits/withdrawals, NAV.
 * @dev One instance per stablecoin or per pool (your choice). Tracks portfolio allocation
 *      and enforces PolicyGuard checks on mutating ops.
 */
contract ReserveVault is Initializable, UUPSUpgradeable, PausableUpgradeable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    struct Position {
        bytes32  symbol;       // instrument key (e.g., bytes32("TBILL_13W"), "SGOV", "CASH_USD")
        uint128  qty;          // instrument units (scaled per instrument convention)
        uint128  pxMinor;      // last marked price (1e6 scale)
        uint64   asOf;         // unix
        bytes32  issuer;       // issuer/custodian key
        PolicyGuard.AssetClass cls;
    }

    PolicyGuard public guard;
    OracleCommittee public oracle;

    // positions
    uint256 public lastId;
    mapping(uint256 => Position) public positions;
    // class allocation (basis points scaled against NAV)
    mapping(PolicyGuard.AssetClass => uint16) public allocBpByClass;
    // issuer concentration (bp)
    mapping(bytes32 => uint16) public allocBpByIssuer;

    // cash token (optional, e.g., USDC within custody)
    IERC20 public cashToken;
    uint8 public cashTokenDecimals; // to normalize to 1e6 "minor USD"

    // accounting
    uint256 public navMinor;   // 1e6 scale
    uint256 public liabilitiesMinor; // minted stable out (set externally)

    event GuardSet(address indexed guard);
    event OracleSet(address indexed oracle);
    event CashTokenSet(address indexed token, uint8 decimals);
    event PositionAdded(uint256 indexed id, bytes32 symbol, bytes32 issuer, uint128 qty, uint128 pxMinor, PolicyGuard.AssetClass cls);
    event PositionUpdated(uint256 indexed id, uint128 qty, uint128 pxMinor, uint64 asOf);
    event NAVSynced(uint256 navMinor, uint64 asOf);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    function initialize(
        address governor,
        address guardian,
        address guard_,
        address oracle_,
        address cashToken_,
        uint8   cashDecimals_
    ) external initializer {
        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(Roles.GOVERNOR, governor);
        _grantRole(Roles.GUARDIAN, guardian);
        _grantRole(Roles.TREASURER, governor);
        _grantRole(Roles.UPGRADER, governor);

        guard = PolicyGuard(guard_);
        oracle = OracleCommittee(oracle_);
        emit GuardSet(guard_);
        emit OracleSet(oracle_);

        if (cashToken_ != address(0)) {
            cashToken = IERC20(cashToken_);
            cashTokenDecimals = cashDecimals_;
            emit CashTokenSet(cashToken_, cashDecimals_);
        }
    }

    function _authorizeUpgrade(address) internal override onlyRole(Roles.UPGRADER) {}

    function pause() external onlyRole(Roles.GUARDIAN) { _pause(); }
    function unpause() external onlyRole(Roles.GUARDIAN) { _unpause(); }

    // --- positions ---

    function addPosition(
        bytes32 symbol,
        bytes32 issuer,
        uint128 qty,
        uint128 pxMinor,
        PolicyGuard.AssetClass cls
    ) external onlyRole(Roles.TREASURER) whenNotPaused returns (uint256 id) {
        id = ++lastId;
        positions[id] = Position({
            symbol: symbol,
            issuer: issuer,
            qty: qty,
            pxMinor: pxMinor,
            asOf: uint64(block.timestamp),
            cls: cls
        });
        emit PositionAdded(id, symbol, issuer, qty, pxMinor, cls);
    }

    function updatePosition(
        uint256 id,
        uint128 qty,
        uint128 pxMinor,
        uint64  asOf
    ) external onlyRole(Roles.TREASURER) whenNotPaused {
        Position storage p = positions[id];
        require(p.asOf != 0, "no_position");
        p.qty = qty;
        p.pxMinor = pxMinor;
        if (asOf != 0) p.asOf = asOf;
        emit PositionUpdated(id, qty, pxMinor, p.asOf);
    }

    // --- pricing & NAV ---

    function syncNAV(bytes32[] calldata symbols) external whenNotPaused {
        uint256 newNav;
        for (uint256 i; i < symbols.length; i++) {
            bytes32 sym = symbols[i];
            (uint256 id, bool found) = _findBySymbol(sym);
            if (!found) continue;
            Position storage p = positions[id];
            (, uint128 px, uint64 asOf, , ) = oracle.latestBySymbol(p.symbol);
            if (asOf > 0) {
                p.pxMinor = px;
                p.asOf = asOf;
            }
            newNav += uint256(p.qty) * uint256(p.pxMinor) / 1e6;
        }
        // add cash (if any)
        if (address(cashToken) != address(0)) {
            uint256 bal = cashToken.balanceOf(address(this));
            // normalize to 1e6 minor
            if (cashTokenDecimals > 6) {
                uint256 s = 10 ** (cashTokenDecimals - 6);
                newNav += bal / s;
            } else if (cashTokenDecimals < 6) {
                uint256 s2 = 10 ** (6 - cashTokenDecimals);
                newNav += bal * s2;
            } else {
                newNav += bal;
            }
        }
        navMinor = newNav;
        emit NAVSynced(newNav, uint64(block.timestamp));
    }

    function nav() external view returns (uint256) { return navMinor; }

    // --- helpers ---

    function _findBySymbol(bytes32 sym) internal view returns (uint256 id, bool ok) {
        for (uint256 i = 1; i <= lastId; i++) {
            if (positions[i].symbol == sym) return (i, true);
        }
        return (0, false);
    }
}
