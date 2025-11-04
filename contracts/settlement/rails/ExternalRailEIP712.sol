// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRail} from "./IRail.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title ExternalRailEIP712
/// @notice Off-chain rail that requires an EIP-712 signed receipt from an approved signer to mark release/refund
contract ExternalRailEIP712 is IRail, EIP712 {
    using ECDSA for bytes32;

    address public admin;
    mapping(address => bool) public isSigner; // bank/shared-ledger signer allowlist

    mapping(bytes32 => Status) private _status;

    bytes32 public constant RECEIPT_TYPEHASH = keccak256(
        "Receipt(bytes32 id,bool released,uint64 settledAt)"
    );

    event AdminTransferred(address indexed from, address indexed to);
    event SignerSet(address indexed signer, bool allowed);

    modifier onlyAdmin(){ require(msg.sender==admin, "X712: not admin"); _; }

    constructor(address _admin) EIP712("ExternalRailEIP712", "1") {
        require(_admin!=address(0), "X712: 0");
        admin = _admin;
    }

    function transferAdmin(address to) external onlyAdmin { require(to!=address(0), "X712: 0"); emit AdminTransferred(admin,to); admin=to; }
    function setSigner(address s, bool allowed) external onlyAdmin { isSigner[s] = allowed; emit SignerSet(s, allowed); }

    function kind() external pure override returns (Kind){ return Kind.EXTERNAL; }

    function transferId(Transfer calldata t) public pure returns (bytes32){
        // Domain-separate with a salt and hash dynamic metadata to a fixed-length value
        return keccak256(abi.encode("X712", t.asset, t.from, t.to, t.amount, keccak256(t.metadata)));
    }

    function prepare(Transfer calldata t) external payable override {
        bytes32 id = transferId(t);
        require(_status[id] == Status.NONE, "X712: exists");
        _status[id] = Status.PREPARED;
        emit RailPrepared(id, t.from, t.to, t.asset, t.amount);
    }

    /// @notice Hash helper to compute EIP-712 digest for Receipt
    function hashReceipt(bytes32 id, bool released, uint64 settledAt) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(RECEIPT_TYPEHASH, id, released, settledAt)));
    }

    function _verify(bytes32 id, bool released, uint64 settledAt, bytes calldata sig) internal view returns (address) {
        bytes32 digest = hashReceipt(id, released, settledAt);
        return ECDSA.recover(digest, sig);
    }

    function markWithReceipt(Transfer calldata t, bool released, uint64 settledAt, bytes calldata sig) external {
        bytes32 id = transferId(t);
        require(_status[id] == Status.PREPARED, "X712: bad state");
        address signer = _verify(id, released, settledAt, sig);
        require(isSigner[signer], "X712: bad signer");
        if (released) {
            _status[id] = Status.RELEASED;
            emit RailReleased(id, t.to, t.asset, t.amount);
        } else {
            _status[id] = Status.REFUNDED;
            emit RailRefunded(id, t.from, t.asset, t.amount);
        }
    }

    // IRail compatibility (admin paths disabled)
    function release(bytes32 /*id*/, Transfer calldata /*t*/) external override onlyAdmin { revert("X712: use markWithReceipt"); }
    function refund(bytes32 /*id*/, Transfer calldata /*t*/) external override onlyAdmin { revert("X712: use markWithReceipt"); }
    function status(bytes32 id) external view override returns (Status){ return _status[id]; }
}
