// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library ISO20022Emitter {
    event ISO20022Pacs009(bytes32 indexed docHash, string uri, uint64 msgId, uint64 txnTs, bytes32 indexed participantLEI);
    event ISO20022Camt053(bytes32 indexed stmtHash, string uri, uint64 asOfTs);

    function emitPacs009(bytes32 docHash, string memory uri, uint64 msgId, uint64 txnTs, bytes32 participantLEI) internal {
        emit ISO20022Pacs009(docHash, uri, msgId, txnTs, participantLEI);
    }
    function emitCamt053(bytes32 stmtHash, string memory uri, uint64 asOfTs) internal {
        emit ISO20022Camt053(stmtHash, uri, asOfTs);
    }
}
