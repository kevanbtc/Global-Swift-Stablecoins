// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title BankAccountProofOracle
/// @notice Verifies and records EIP-712 signed bank account PoR statements on-chain.
contract BankAccountProofOracle is AccessControl, EIP712 {
    bytes32 public constant ROLE_ADMIN     = keccak256("ROLE_ADMIN");
    bytes32 public constant ROLE_PUBLISHER = keccak256("ROLE_PUBLISHER"); // can submit verified proofs
    bytes32 public constant ROLE_SIGNER    = keccak256("ROLE_SIGNER");    // authorized off-chain signers

    struct Proof {
        // business fields
        string  bankName;       // "JP Morgan N.A."
        string  accountRef;     // masked IBAN or internal ref "US-0723-***-0442"
        string  ccy;           // "USD"
        uint64  statementDate; // y-m-d 00:00 UTC
        uint64  asOf;         // measured timestamp
        uint256 closingBalanceMinor; // minor units (cents)
        bytes32 docHash;      // keccak256 of statement/CSV/PDF (optional)
        string  docURI;       // ipfs://... or https://... (optional)
        // derived/meta
        address signer;       // signer used
        bool    revoked;
        uint64  createdAt;
    }

    // versioning: (accountRef, statementDate) -> versionId
    mapping(bytes32 => uint256) public latestVersionId;
    // versioned proofs: id => Proof
    mapping(uint256 => Proof) public proofs;
    uint256 public lastId;

    event ProofSubmitted(uint256 indexed id, string bankName, string accountRef, string ccy, uint256 closingBalanceMinor, address indexed signer, bytes32 docHash, string docURI);
    event ProofRevoked(uint256 indexed id);
    event SignerSet(address indexed signer, bool allowed);

    // EIP-712 type hash
    bytes32 private constant _PROOF_TYPEHASH = keccak256(
        "BankStatement(string bankName,string accountRef,string ccy,uint64 statementDate,uint64 asOf,uint256 closingBalanceMinor,bytes32 docHash,string docURI)"
    );

    constructor(address admin)
        EIP712("BankAccountProofOracle","1")
    {
        _grantRole(ROLE_ADMIN, admin);
        _grantRole(ROLE_PUBLISHER, admin);
        _grantRole(ROLE_SIGNER, admin);
    }

    function setSigner(address s, bool allowed) external onlyRole(ROLE_ADMIN) {
        if (allowed) _grantRole(ROLE_SIGNER, s);
        else _revokeRole(ROLE_SIGNER, s);
        emit SignerSet(s, allowed);
    }

    function _hashProof(
        string memory bankName,
        string memory accountRef,
        string memory ccy,
        uint64 statementDate,
        uint64 asOf,
        uint256 closingBalanceMinor,
        bytes32 docHash,
        string memory docURI
    ) internal view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(
            _PROOF_TYPEHASH,
            keccak256(bytes(bankName)),
            keccak256(bytes(accountRef)),
            keccak256(bytes(ccy)),
            statementDate,
            asOf,
            closingBalanceMinor,
            docHash,
            keccak256(bytes(docURI))
        )));
    }

    /// @notice Submit a signed PoR statement; signature must be by ROLE_SIGNER.
    function submitProof(
        string calldata bankName,
        string calldata accountRef,
        string calldata ccy,
        uint64 statementDate,
        uint64 asOf,
        uint256 closingBalanceMinor,
        bytes32 docHash,
        string calldata docURI,
        bytes calldata signature
    ) external onlyRole(ROLE_PUBLISHER) returns (uint256 id) {
        bytes32 digest = _hashProof(bankName, accountRef, ccy, statementDate, asOf, closingBalanceMinor, docHash, docURI);
        address signer = ECDSA.recover(digest, signature);
        require(hasRole(ROLE_SIGNER, signer), "unauthorized signer");

        id = ++lastId;
        proofs[id] = Proof({
            bankName: bankName,
            accountRef: accountRef,
            ccy: ccy,
            statementDate: statementDate,
            asOf: asOf,
            closingBalanceMinor: closingBalanceMinor,
            docHash: docHash,
            docURI: docURI,
            signer: signer,
            revoked: false,
            createdAt: uint64(block.timestamp)
        });

        // set latest pointer for (accountRef, statementDate)
        bytes32 key = keccak256(abi.encodePacked(accountRef, ":", statementDate));
        latestVersionId[key] = id;

        emit ProofSubmitted(id, bankName, accountRef, ccy, closingBalanceMinor, signer, docHash, docURI);
    }

    function revoke(uint256 id) external onlyRole(ROLE_ADMIN) {
        Proof storage p = proofs[id];
        require(!p.revoked, "already revoked");
        p.revoked = true;
        emit ProofRevoked(id);
    }

    function latestFor(string calldata accountRef, uint64 statementDate) external view returns (uint256 id, Proof memory p) {
        bytes32 key = keccak256(abi.encodePacked(accountRef, ":", statementDate));
        id = latestVersionId[key];
        p = proofs[id];
    }
}
