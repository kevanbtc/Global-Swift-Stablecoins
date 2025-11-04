// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable as AC} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Errors} from "../common/Errors.sol";

/**
 * @title ReserveManagerUpgradeable
 * @notice MiCA-style reserve snapshots + bucket concentration limits, with attestor role.
 */
contract ReserveManagerUpgradeable is Initializable, AC {
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    bytes32 public constant ATTESTOR_ROLE = keccak256("ATTESTOR_ROLE");

    enum Bucket { T_BILLS, REVERSE_REPO, BANK_DEPOSITS, MMF, CASH_OTHER }
    struct Limits { uint16 maxBps; }
    struct Snapshot { uint256 total; uint256[5] byBucket; uint64 ts; bytes32 proofCid; }

    mapping(Bucket => Limits) public limits;
    Snapshot public last;

    event LimitsSet(Bucket bucket, uint16 maxBps);
    event ReservesAttested(uint256 total, uint256[5] byBucket, uint64 ts, bytes32 proofCid);

    function initialize(address admin, address governor) public initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GOVERNOR_ROLE, governor);
    }

    function setLimit(Bucket b, uint16 maxBps) external onlyRole(GOVERNOR_ROLE) {
        if (maxBps > 10_000) revert Errors.InvalidParam();
        limits[b] = Limits({maxBps: maxBps});
        emit LimitsSet(b, maxBps);
    }

    function attest(uint256 total, uint256[5] calldata byBucket, uint64 ts, bytes32 proofCid)
        external onlyRole(ATTESTOR_ROLE)
    {
        if (total == 0) revert Errors.InvalidParam();
        uint256 sum;
        for (uint256 i; i < 5; ++i) sum += byBucket[i];
        if (sum != total) revert Errors.InvalidParam();

        for (uint256 i; i < 5; ++i) {
            uint16 cap = limits[Bucket(i)].maxBps;
            if (cap == 0) continue;
            uint256 bps = (byBucket[i] * 10_000) / total;
            if (bps > cap) revert Errors.ConcentrationBreach();
        }
        last = Snapshot({total: total, byBucket: byBucket, ts: ts, proofCid: proofCid});
        emit ReservesAttested(total, byBucket, ts, proofCid);
    }

    function coverageBps(uint256 liabilities) external view returns (uint16 cov) {
        if (liabilities == 0) return type(uint16).max;
        uint256 c = (last.total * 10_000) / liabilities;
        cov = c > type(uint16).max ? type(uint16).max : uint16(c);
    }
}
