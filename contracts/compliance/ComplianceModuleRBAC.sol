// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IComplianceGate {
    function check(address from, address to, address asset, uint256 amount, bytes calldata context) external view returns (bool ok, bytes memory reason);
}

interface ISanctionsView { function isSanctioned(address a) external view returns (bool); }

interface IKYC { function records(address who) external view returns (bool approved, bytes32 jurisdiction, bytes32 riskTier, uint64 updatedAt); }

/**
 * @title ComplianceModuleRBAC
 * @notice Reference compliance gate. Uses:
 *         - KYCRegistry (approved parties)
 *         - SanctionsOracleDenylist (deny sanctioned parties)
 *         - Asset allowlist (optional)
 * Context convention (optional): first 32 bytes may be a ruleProfileId (keccak256).
 */
contract ComplianceModuleRBAC is IComplianceGate {
    address public admin;
    IKYC public kyc;
    ISanctionsView public sanctions;

    mapping(address => bool) public assetAllowed;   // ERC20/ERC721/ERC1155 contract addresses

    event AdminTransferred(address indexed from, address indexed to);
    event KYCSet(address indexed kyc);
    event SanctionsSet(address indexed oracle);
    event AssetAllowed(address indexed asset, bool allowed);

    modifier onlyAdmin() { require(msg.sender == admin, "CM: not admin"); _; }
    constructor(address _admin, address _kyc, address _sanctions) {
        require(_admin != address(0), "CM: admin 0"); admin = _admin; kyc = IKYC(_kyc); sanctions = ISanctionsView(_sanctions);
    }

    function transferAdmin(address to) public onlyAdmin { require(to != address(0), "CM: 0"); emit AdminTransferred(admin, to); admin = to; }
    function setKYC(address k) public onlyAdmin { kyc = IKYC(k); emit KYCSet(k); }
    function setSanctions(address s) public onlyAdmin { sanctions = ISanctionsView(s); emit SanctionsSet(s); }
    function setAssetAllowed(address asset, bool allowed) public onlyAdmin { assetAllowed[asset] = allowed; emit AssetAllowed(asset, allowed); }

    function check(address from, address to, address asset, uint256 /*amount*/, bytes calldata /*context*/) public view override returns (bool ok, bytes memory reason) {
        // Sanctions
        if (address(sanctions) != address(0)) {
            if (sanctions.isSanctioned(from) || sanctions.isSanctioned(to)) return (false, bytes("SANCTIONED"));
        }
        // KYC approvals
        if (address(kyc) != address(0)) {
            (bool aApproved,,,) = kyc.records(from); (bool bApproved,,,) = kyc.records(to);
            if (!aApproved || !bApproved) return (false, bytes("KYC_NOT_APPROVED"));
        }
        // Asset allowlist (optional)
        if (asset != address(0) && assetAllowed[asset] == false) return (false, bytes("ASSET_NOT_ALLOWED"));
        return (true, bytes(""));
    }
}
