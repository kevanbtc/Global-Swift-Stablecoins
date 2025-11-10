// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title ReserveManager
 * @notice MiCA-style reserve accounting with bucket limits and attestation workflow.
 *         Buckets: T-BILLS, REVERSE_REPO, BANK_DEPOSITS, MMF, CASH_OTHER.
 *         Constraints expressed as basis points of TOTAL assets (concentration caps).
 */
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract ReserveManager is AccessControl {
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    bytes32 public constant ATTESTOR_ROLE = keccak256("ATTESTOR_ROLE");

    enum Bucket { T_BILLS, REVERSE_REPO, BANK_DEPOSITS, MMF, CASH_OTHER }

    struct Limits { uint16 maxBps; }           // max % of total assets for the bucket
    struct Snapshot { uint256 total; uint256[5] byBucket; uint64 ts; bytes32 proofCid; }

    mapping(Bucket => Limits) public limits;
    Snapshot public last;

    event LimitsSet(Bucket bucket, uint16 maxBps);
    event ReservesAttested(uint256 total, uint256[5] byBucket, uint64 ts, bytes32 proofCid);

    constructor(address admin, address governor) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GOVERNOR_ROLE, governor);
    }

    function setLimit(Bucket b, uint16 maxBps) public onlyRole(GOVERNOR_ROLE) {
        require(maxBps <= 10_000, "bps");
        limits[b] = Limits({maxBps: maxBps});
        emit LimitsSet(b, maxBps);
    }

    function attest(uint256 total, uint256[5] calldata byBucket, uint64 ts, bytes32 proofCid) public onlyRole(ATTESTOR_ROLE)
    {
        require(total > 0, "total=0");
        uint256 sum;
        for (uint256 i = 0; i < 5; i++) {
            sum += byBucket[i];
        }
        require(sum == total, "sum!=total");

        // concentration checks
        for (uint256 i = 0; i < 5; i++) {
            uint16 cap = limits[Bucket(i)].maxBps;
            if (cap > 0) {
                uint256 bps = (byBucket[i] * 10_000) / total;
                require(bps <= cap, "concentration");
            }
        }

        last = Snapshot({total: total, byBucket: byBucket, ts: ts, proofCid: proofCid});
        emit ReservesAttested(total, byBucket, ts, proofCid);
    }

    function coverageBps(uint256 liabilities) public view returns (uint16 cov) {
        if (liabilities == 0) return type(uint16).max;
        uint256 c = (last.total * 10_000) / liabilities;
        cov = c > type(uint16).max ? type(uint16).max : uint16(c);
    }
}
