// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Minimal compatibility shim for legacy ECDSAUpgradeable API.
// Delegates to non-upgradeable ECDSA and inlines typed-data/hash helpers.
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

library ECDSAUpgradeable {
    enum RecoverError { NoError, InvalidSignature, InvalidSignatureLength, InvalidSignatureS, InvalidSignatureV }

    function tryRecover(bytes32 hash, bytes memory signature) internal pure returns (address, RecoverError) {
        // ECDSA.tryRecover returns (address, ECDSA.RecoverError, bytes32)
        (address signer, ECDSA.RecoverError err, bytes32 _arg) = ECDSA.tryRecover(hash, signature);
        _arg; // silence unused var
        return (signer, _mapErr(err));
    }

    function recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        return ECDSA.recover(hash, signature);
    }

    // Legacy helpers kept for compatibility (prefer MessageHashUtils in v5).
    function toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function _mapErr(ECDSA.RecoverError err) private pure returns (RecoverError) {
        if (err == ECDSA.RecoverError.NoError) return RecoverError.NoError;
        if (err == ECDSA.RecoverError.InvalidSignature) return RecoverError.InvalidSignature;
        if (err == ECDSA.RecoverError.InvalidSignatureLength) return RecoverError.InvalidSignatureLength;
        if (err == ECDSA.RecoverError.InvalidSignatureS) return RecoverError.InvalidSignatureS;
        return RecoverError.InvalidSignatureV;
    }
}
