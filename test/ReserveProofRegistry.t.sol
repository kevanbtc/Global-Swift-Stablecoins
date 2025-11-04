// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/ReserveProofRegistry.sol";

contract ReserveProofRegistryTest is Test {
    ReserveProofRegistry reg;

    address admin    = address(0xA11CE);
    address governor = address(0xB0B);
    address reporter = address(0xC0DE);
    uint256 auditorPK = 0x1234;
    address auditor;

    function setUp() public {
        auditor = vm.addr(auditorPK);

        // deploy implementation
        reg = new ReserveProofRegistry();
        // simulate UUPS proxy by calling initializer directly on impl (ok for unit test)
        vm.prank(address(this));
        reg.initialize(admin, governor);

        // grant roles
        vm.startPrank(admin);
        bytes32 REPORTER_ROLE = keccak256("REPORTER_ROLE");
        bytes32 AUDITOR_ROLE  = keccak256("AUDITOR_ROLE");
        reg.grantRole(REPORTER_ROLE, reporter);
        reg.grantRole(AUDITOR_ROLE, auditor);
        vm.stopPrank();
    }

    function testSubmit() public {
        bytes32 reserveId = keccak256("USDC_RESERVE_TBILLS");
        bytes32 cid = bytes32(uint256(0xABCDEF));

        ReserveProofRegistry.ReserveAttestation memory att = ReserveProofRegistry.ReserveAttestation({
            reserveId: reserveId,
            auditor: auditor,
            start: uint64(block.timestamp - 1 hours),
            end: uint64(block.timestamp),
            validUntil: uint64(block.timestamp + 7 days),
            totalAssets: 1_000_000e6,
            totalLiabilities: 990_000e6,
            cid: cid,
            nonce: 1
        });

        bytes32 typeHash = reg.ATTESTATION_TYPEHASH();
        bytes32 structHash = keccak256(
            abi.encode(
                typeHash,
                att.reserveId,
                att.auditor,
                att.start,
                att.end,
                att.validUntil,
                att.totalAssets,
                att.totalLiabilities,
                att.cid,
                att.nonce
            )
        );
        bytes32 digest = reg.domainSeparator();
        // _hashTypedDataV4 = keccak256("\x19\x01" || domainSeparator || structHash)
        bytes32 fullDigest = keccak256(abi.encodePacked("\x19\x01", digest, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(auditorPK, fullDigest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.prank(reporter);
        reg.submitReserveAttestation(att, sig);

        ReserveProofRegistry.StoredAttestation memory st = reg.latest(reserveId);
        assertEq(st.auditor, auditor);
        assertEq(st.nonce, 1);
        assertEq(st.cid, cid);
        assertEq(st.digest, fullDigest);
    }
}
