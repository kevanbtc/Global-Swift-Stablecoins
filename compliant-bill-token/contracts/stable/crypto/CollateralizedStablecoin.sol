// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {StableErrors} from "../common/StableErrors.sol";

/**
 * Simplified crypto-collateralized stablecoin with per-asset collateral types.
 * - Add/remove collateral (no custody moves here; assume ERC20 collateral under separate vault adapter in production)
 * - Mint/burn debt (stablecoin) respecting collateralization and ceilings
 * - Liquidate undercollateralized positions with penalty
 */
contract CollateralizedStablecoin is ERC20, ERC20Permit, AccessControl, Pausable {
    using StableErrors for *;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant RISK_ROLE  = keccak256("RISK_ROLE");
    bytes32 public constant KEEPER_ROLE= keccak256("KEEPER_ROLE");

    struct CollateralType {
        bool listed;
        uint256 debtCeiling;        // max total debt in this collateral
        uint16  liqRatioBps;        // e.g., 15000 = 150%
        uint16  stabilityFeeBps;    // annualized, applied offchain or via keeper
        uint16  penaltyBps;         // liquidation penalty
        IPriceOracle oracle;        // priceE18
    }

    struct Vault { uint256 collat; uint256 debt; } // per-asset vault; keyed by (owner, asset)

    mapping(address => CollateralType) public collatTypes; // asset -> params
    mapping(address => mapping(address => Vault)) public vaults; // owner -> asset -> vault
    mapping(address => uint256) public totalDebtByAsset; // asset -> debt

    event CollateralListed(address indexed asset, uint256 ceiling, uint16 liqRatio, uint16 fee, uint16 penalty, address oracle);
    event VaultUpdated(address indexed owner, address indexed asset, uint256 collat, uint256 debt);
    event Liquidated(address indexed owner, address indexed asset, uint256 repaid, uint256 seized);

    constructor(address admin) ERC20("Crypto Collateral Stablecoin", "cUSD") ERC20Permit("Crypto Collateral Stablecoin") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(RISK_ROLE, admin);
        _grantRole(KEEPER_ROLE, admin);
    }

    function pause() external onlyRole(ADMIN_ROLE) { _pause(); }
    function unpause() external onlyRole(ADMIN_ROLE) { _unpause(); }

    function listCollateral(address asset, CollateralType calldata c) external onlyRole(RISK_ROLE) {
        require(c.liqRatioBps >= 10000, "liqRatio<100%");
        collatTypes[asset] = c; emit CollateralListed(asset, c.debtCeiling, c.liqRatioBps, c.stabilityFeeBps, c.penaltyBps, address(c.oracle));
    }

    function _valueE18(address asset, uint256 amount) internal view returns (uint256 v) {
        CollateralType memory c = collatTypes[asset]; if (!c.listed) revert StableErrors.CollateralTypeNotFound();
        (uint256 p, ) = c.oracle.priceE18(asset); v = (amount * p) / 1e18;
    }

    function _safeAfter(address owner, address asset, Vault memory v) internal view {
        CollateralType memory c = collatTypes[asset]; if (!c.listed) revert StableErrors.CollateralTypeNotFound();
        if (v.debt == 0) return; // safe if no debt
        uint256 val = _valueE18(asset, v.collat);
        if (val * 10000 < uint256(c.liqRatioBps) * v.debt) revert StableErrors.SafeCheckFailed();
    }

    function addCollateral(address asset, uint256 amount) external whenNotPaused {
        Vault memory v = vaults[msg.sender][asset]; v.collat += amount; vaults[msg.sender][asset] = v; emit VaultUpdated(msg.sender, asset, v.collat, v.debt);
    }

    function removeCollateral(address asset, uint256 amount) external whenNotPaused {
        Vault memory v = vaults[msg.sender][asset]; if (v.collat < amount) revert StableErrors.InsufficientBalance(); v.collat -= amount; _safeAfter(msg.sender, asset, v); vaults[msg.sender][asset] = v; emit VaultUpdated(msg.sender, asset, v.collat, v.debt);
    }

    function mint(address asset, uint256 amount) external whenNotPaused {
        CollateralType memory c = collatTypes[asset]; if (!c.listed) revert StableErrors.CollateralTypeNotFound();
        Vault memory v = vaults[msg.sender][asset]; v.debt += amount; _safeAfter(msg.sender, asset, v);
        if (totalDebtByAsset[asset] + amount > c.debtCeiling) revert StableErrors.SafeCheckFailed();
        totalDebtByAsset[asset] += amount; vaults[msg.sender][asset] = v; _mint(msg.sender, amount); emit VaultUpdated(msg.sender, asset, v.collat, v.debt);
    }

    function burn(address asset, uint256 amount) external whenNotPaused {
        Vault memory v = vaults[msg.sender][asset]; if (v.debt < amount) revert StableErrors.InsufficientBalance(); v.debt -= amount; totalDebtByAsset[asset] -= amount; vaults[msg.sender][asset] = v; _burn(msg.sender, amount); emit VaultUpdated(msg.sender, asset, v.collat, v.debt);
    }

    function liquidate(address owner, address asset, uint256 repay) external whenNotPaused onlyRole(KEEPER_ROLE) {
        CollateralType memory c = collatTypes[asset]; if (!c.listed) revert StableErrors.CollateralTypeNotFound();
        Vault memory v = vaults[owner][asset];
        // check undercollateralized
        uint256 val = _valueE18(asset, v.collat);
        require(val * 10000 < uint256(c.liqRatioBps) * v.debt, "not undercollateralized");
        uint256 rep = repay > v.debt ? v.debt : repay;
        uint256 seize = (rep * (10000 + c.penaltyBps)) / 10000; // simplistic seize, in stable terms
        // convert seize (stable) to collateral units using price
        (uint256 p,) = c.oracle.priceE18(asset);
        uint256 seizeUnits = (seize * 1e18) / p; if (seizeUnits > v.collat) seizeUnits = v.collat;
        v.debt -= rep; v.collat -= seizeUnits; totalDebtByAsset[asset] -= rep; vaults[owner][asset] = v; _burn(msg.sender, 0); // keeper handles funds offchain; stable burn 0 no-op
        emit Liquidated(owner, asset, rep, seizeUnits); emit VaultUpdated(owner, asset, v.collat, v.debt);
    }
}
