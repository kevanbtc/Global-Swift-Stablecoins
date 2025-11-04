// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

interface IReportableVault {
    // must be the same signature we exposed on ERC4626TBillVaultUpgradeable
    function report(uint256 newTotalAssets) external;
    function CUSTODIAN() external view returns (bytes32);
}

/// @title CustodianNavReporter
/// @notice Holds CUSTODIAN role on target vault(s) and forwards EIP-712 signed NAV reports
///         from off-chain custodians. Provides replay protection and expiry.
contract CustodianNavReporter is AccessControl, EIP712 {
    using ECDSA for bytes32;

    bytes32 public constant ADMIN = keccak256("ADMIN");
    bytes32 public constant VAULT_SETTER = keccak256("VAULT_SETTER");

    struct NAVReport {
        address vault;
        uint256 totalAssets; // in asset units
        uint64  navTime;     // when NAV was produced off-chain
        uint64  validUntil;  // report expiry
        uint256 nonce;       // replay protection per vault
    }

    bytes32 public constant NAVREPORT_TYPEHASH = keccak256(
        "NAVReport(address vault,uint256 totalAssets,uint64 navTime,uint64 validUntil,uint256 nonce)"
    );

    // authorized signers (off-chain custodians)
    mapping(address => bool) public signerAllowed;
    // per-vault nonce => consumed
    mapping(address => mapping(uint256 => bool)) public nonceUsed;

    event SignerSet(address indexed signer, bool allowed);
    event ReportForwarded(address indexed vault, uint256 totalAssets, uint64 navTime, uint64 validUntil, uint256 nonce);

    constructor(address governor) EIP712("CustodianNavReporter","1") {
        _grantRole(DEFAULT_ADMIN_ROLE, governor);
        _grantRole(ADMIN, governor);
        _grantRole(VAULT_SETTER, governor);
    }

    function setSigner(address signer, bool allowed) external onlyRole(ADMIN) {
        signerAllowed[signer] = allowed;
        emit SignerSet(signer, allowed);
    }

    /// @notice Call from admin after deploying vaults: grant this reporter the CUSTODIAN role at vaults.
    function setupVaultRole(IReportableVault vault) external onlyRole(VAULT_SETTER) {
        // The admin of vault must have already granted this contract CUSTODIAN on the vault.
        // This function is mainly here to sanity-check the role hash exists and is readable.
        vault.CUSTODIAN();
    }

    function submitSignedReport(NAVReport calldata r, bytes calldata signature) external {
        require(r.vault != address(0) && r.totalAssets > 0, "bad_report");
        require(block.timestamp <= r.validUntil, "expired");
        require(!nonceUsed[r.vault][r.nonce], "replay");

        address signer = _recover(r, signature);
        require(signerAllowed[signer], "unauth_signer");

        nonceUsed[r.vault][r.nonce] = true;
        IReportableVault(r.vault).report(r.totalAssets);
        emit ReportForwarded(r.vault, r.totalAssets, r.navTime, r.validUntil, r.nonce);
    }

    function _recover(NAVReport calldata r, bytes calldata signature) internal view returns (address) {
        bytes32 structHash = keccak256(abi.encode(
            NAVREPORT_TYPEHASH, r.vault, r.totalAssets, r.navTime, r.validUntil, r.nonce
        ));
        bytes32 digest = _hashTypedDataV4(structHash);
        return ECDSA.recover(digest, signature);
    }
}
