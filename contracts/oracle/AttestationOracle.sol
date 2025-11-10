// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {PolicyRoles} from "../governance/PolicyRoles.sol";
import {IAttestationOracle} from "../interfaces/IAttestationOracle.sol";

/// @title AttestationOracle
/// @notice Minimal quorum-based reserve attestation registry (push by ORACLE role or signed relays)
contract AttestationOracle is AccessControl, IAttestationOracle {
    struct QuorumCfg { uint8 threshold; address[] signers; mapping(address=>bool) isSigner; }

    mapping(bytes32 => ReserveReport) private _latest;
    mapping(bytes32 => QuorumCfg) private _quorum;

    event ReportSubmitted(bytes32 indexed reserveId, uint256 timestamp, uint256 liabilities, uint256 reserves, string uri);
    event QuorumSet(bytes32 indexed reserveId, uint8 threshold, address[] signers);

    constructor(address admin) {
        _grantRole(PolicyRoles.ROLE_ADMIN, admin);
        _grantRole(PolicyRoles.ROLE_ORACLE, admin);
    }

    function setQuorum(bytes32 reserveId, uint8 threshold, address[] calldata signers) public onlyRole(PolicyRoles.ROLE_ADMIN) {
        require(threshold > 0 && threshold <= signers.length, "bad quorum");
        QuorumCfg storage q = _quorum[reserveId];
        // reset
        for (uint256 i=0;i<q.signers.length;i++){ q.isSigner[q.signers[i]] = false; }
        q.signers = signers;
        q.threshold = threshold;
        for (uint256 i=0;i<signers.length;i++){ q.isSigner[signers[i]] = true; }
        emit QuorumSet(reserveId, threshold, signers);
    }

    function submit(ReserveReport calldata rr, address[] calldata signersApproved) public onlyRole(PolicyRoles.ROLE_ORACLE) {
        // lightweight "quorum evidence": the caller declares which approved signers pre-validated the payload
        QuorumCfg storage q = _quorum[rr.reserveId];
        require(q.threshold > 0, "no quorum");
        uint256 ok;
        for (uint256 i=0;i<signersApproved.length;i++){
            if (q.isSigner[signersApproved[i]]) ok++;
        }
        require(ok >= q.threshold, "quorum fail");
        _latest[rr.reserveId] = rr;
        emit ReportSubmitted(rr.reserveId, rr.timestamp, rr.totalLiabilities, rr.totalReserves, rr.uri);
    }

    function latest(bytes32 reserveId) public view returns (ReserveReport memory ok, bool exists) {
        ReserveReport memory r = _latest[reserveId];
        return (r, r.timestamp != 0);
    }

    function hasQuorum(bytes32 reserveId) public view returns (bool) {
        return _quorum[reserveId].threshold > 0;
    }
}
