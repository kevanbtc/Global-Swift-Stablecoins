// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PolicyRoles} from "../governance/PolicyRoles.sol";
import {IAttestationOracle} from "../interfaces/IAttestationOracle.sol";
import {IProofOfReserves} from "../interfaces/IProofOfReserves.sol";

/// @title ReserveManager
/// @notice Tracks backing reserves for a stablecoin/RWA and gates mint/redeem via attestations
contract ReserveManager is AccessControl, IProofOfReserves {
    struct ReserveSlot {
        bytes32 reserveId;       // link to oracle feed
        address custodianWallet; // off-chain custodian escrow address mirror (optional)
        address[] assets;        // ERC20s held on-chain for backing
    }

    IAttestationOracle public oracle;
    address public issuer;       // stablecoin/RWA token allowed to call checks

    mapping(bytes32 => ReserveSlot) public reserves;

    event ReserveRegistered(bytes32 indexed id, address[] assets);
    event OracleSet(address indexed oracle);
    event IssuerSet(address indexed issuer);

    constructor(address admin, IAttestationOracle o) {
        _grantRole(PolicyRoles.ROLE_ADMIN, admin);
        _grantRole(PolicyRoles.ROLE_TREASURER, admin);
        oracle = o;
        emit OracleSet(address(o));
    }

    function setIssuer(address _issuer) external onlyRole(PolicyRoles.ROLE_ADMIN) {
        issuer = _issuer;
        emit IssuerSet(_issuer);
    }

    function registerReserve(bytes32 id, address custodianWallet, address[] calldata assets) external onlyRole(PolicyRoles.ROLE_ADMIN) {
        reserves[id] = ReserveSlot({reserveId:id, custodianWallet:custodianWallet, assets:assets});
        emit ReserveRegistered(id, assets);
    }

    // --- IProofOfReserves
    function checkMint(bytes32 reserveId, uint256 amount) external view returns (bool) {
        require(msg.sender == issuer, "only issuer");
        (IAttestationOracle.ReserveReport memory r, bool ok) = oracle.latest(reserveId);
        if (!ok) return false;
        // naive guard: require reserves - liabilities >= amount (unit-consistent)
        if (r.totalReserves < r.totalLiabilities + amount) return false;
        return true;
    }

    function checkRedeem(bytes32 reserveId, uint256 amount) external view returns (bool) {
        require(msg.sender == issuer, "only issuer");
        (IAttestationOracle.ReserveReport memory r, bool ok) = oracle.latest(reserveId);
        if (!ok) return false;
        // allow redeem if liabilities >= amount (simple solvency guard)
        if (r.totalLiabilities < amount) return false;
        return true;
    }
}
