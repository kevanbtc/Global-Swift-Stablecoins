// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {IPriceOracle} from "../../stable/interfaces/IPriceOracle.sol";
import {ISO20022Emitter} from "../../utils/ISO20022Emitter.sol";

/// @title MiCA ART-style Asset Referenced Basket Token (upgradeable)
/// @notice Basket weights with oracle pricing. Mint/burn by cashier with ISO audit events.
contract AssetReferencedBasketUpgradeable is Initializable, UUPSUpgradeable, ERC20Upgradeable, ERC20PermitUpgradeable, AccessControlUpgradeable, PausableUpgradeable {
    using ISO20022Emitter for *;

    bytes32 public constant ADMIN_ROLE   = keccak256("ADMIN_ROLE");
    bytes32 public constant CASHIER_ROLE = keccak256("CASHIER_ROLE");

    struct Component { address asset; uint16 weightBps; IPriceOracle oracle; }
    Component[] public components;
    uint16 public totalWeightBps; // must be 10000

    uint16 public minReserveRatioBps; // ART reserve floor, typically 10000

    event ComponentSet(uint256 index, address asset, uint16 weightBps, address oracle);
    event ComponentsReset(uint16 totalWeight);
    event MinReserveRatioSet(uint16 bps);

    function initialize(address admin, string memory name_, string memory symbol_, uint16 minRRBps) public initializer {
        __ERC20_init(name_, symbol_);
        __ERC20Permit_init(name_);
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        minReserveRatioBps = minRRBps;
        emit MinReserveRatioSet(minRRBps);
    }
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function pause() external onlyRole(ADMIN_ROLE){ _pause(); }
    function unpause() external onlyRole(ADMIN_ROLE){ _unpause(); }

    function resetComponents(Component[] calldata list) external onlyRole(ADMIN_ROLE) {
        delete components; totalWeightBps = 0;
        for (uint256 i=0;i<list.length;i++) {
            components.push(list[i]); totalWeightBps += list[i].weightBps;
            emit ComponentSet(i, list[i].asset, list[i].weightBps, address(list[i].oracle));
        }
        require(totalWeightBps == 10000, "weights != 100%");
        emit ComponentsReset(totalWeightBps);
    }

    function setMinReserveRatio(uint16 bps) external onlyRole(ADMIN_ROLE){ minReserveRatioBps = bps; emit MinReserveRatioSet(bps);}    

    function _basketNavE18() public view returns (uint256 nav){
        // assume unit-of-account target is USD, oracles return USD 1e18 per unit asset
        for (uint256 i=0;i<components.length;i++) {
            (uint256 p,) = components[i].oracle.priceE18(components[i].asset);
            nav += (p * components[i].weightBps) / 10000;
        }
    }

    function _enforceReserve(uint256 newSupply) internal view {
        // require total basket NAV per token >= minRR * 1
        uint256 navPer = _basketNavE18(); // nav per token unit
        if (navPer * 10000 < uint256(minReserveRatioBps) * 1e18) revert("reserve floor");
        // In production, you would multiply navPer by backing units held; here we enforce reference NAV per token
        // and rely on offchain custody + audits.
    }

    function mint(address to, uint256 amount, bytes32 pacsHash, string calldata uri, bytes32 lei) external onlyRole(CASHIER_ROLE) whenNotPaused {
        _enforceReserve(totalSupply() + amount); _mint(to, amount);
        ISO20022Emitter.emitPacs009(pacsHash, uri, uint64(block.number), uint64(block.timestamp), lei);
    }
    function burn(address from, uint256 amount, bytes32 pacsHash, string calldata uri, bytes32 lei) external onlyRole(CASHIER_ROLE) whenNotPaused {
        _burn(from, amount);
        ISO20022Emitter.emitPacs009(pacsHash, uri, uint64(block.number), uint64(block.timestamp), lei);
    }
}
