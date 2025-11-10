// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Roles} from "../common/Roles.sol";

/**
 * @title AttestationRegistry
 * @notice Stores signed reserve proofs / NAV attestations off-chain -> on-chain hashes with freshness.
 * @dev EIP-712 envelope to verify designated PROOF_PROVIDER signers.
 */
contract AttestationRegistry is Initializable, UUPSUpgradeable, AccessControlUpgradeable, EIP712Upgradeable {

    struct Attestation {
        bytes32 schema;     // e.g. keccak256("RESERVE_V1")
        bytes32 contentHash;// IPFS/CID or Merkle root hash
        uint64  asOf;       // timestamp from provider (UTC)
        string  uri;        // optional off-chain pointer
    }

    // feed => allowed?
    mapping(address => bool) public providers;
    // latest attestation id
    uint256 public lastId;
    // id => attestation
    mapping(uint256 => Attestation) public atts;

    event ProviderSet(address indexed provider, bool allowed);
    event Attested(uint256 indexed id, address indexed provider, bytes32 schema, bytes32 contentHash, uint64 asOf, string uri);

    bytes32 private constant TYPEHASH =
        keccak256("ReserveAttestation(bytes32 schema,bytes32 contentHash,uint64 asOf,string uri)");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    function initialize(address governor) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __EIP712_init("AttestationRegistry", "1");
        _grantRole(Roles.GOVERNOR, governor);
        _grantRole(Roles.UPGRADER, governor);
        _grantRole(Roles.COMPLIANCE, governor);
    }

    function _authorizeUpgrade(address) internal override onlyRole(Roles.UPGRADER) {}

    function setProvider(address provider, bool allowed) public onlyRole(Roles.GOVERNOR) {
        providers[provider] = allowed;
        emit ProviderSet(provider, allowed);
    }

    function submitAttestation(
        bytes32 schema,
        bytes32 contentHash,
        uint64 asOf,
        string calldata uri,
        bytes calldata sig
    ) public returns (uint256 id) {
        // recover signer
        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(TYPEHASH, schema, contentHash, asOf, keccak256(bytes(uri))))
        );
    address signer = ECDSA.recover(digest, sig);
        require(providers[signer], "unauthorized_provider");

        id = ++lastId;
        atts[id] = Attestation({ schema: schema, contentHash: contentHash, asOf: asOf, uri: uri });
        emit Attested(id, signer, schema, contentHash, asOf, uri);
    }

    function latest() public view returns (uint256 id, Attestation memory a) {
        id = lastId; a = atts[id];
    }
}
