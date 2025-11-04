// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../contracts/compliance/AccessRegistryUpgradeable.sol";
import "../../contracts/compliance/RoleIds.sol";
import "../../contracts/common/Errors.sol";

contract AccessRegistrySigTest is Test {
    AccessRegistryUpgradeable reg;
    address admin; address gov; address signer;
    uint256 adminPk = 0xA11CE;
    uint256 govPk   = 0xB0B;
    uint256 sPk     = 0xC0DE;

    function setUp() public {
        admin = vm.addr(adminPk); gov = vm.addr(govPk); signer = vm.addr(sPk);
        vm.prank(admin);
        reg = new AccessRegistryUpgradeable();
        reg.initialize(admin, gov, "TBAC");
        vm.startPrank(gov);
        reg.grantRole(RoleIds.SIGNER_ROLE, signer);
        vm.stopPrank();
    }

    function _att(address subject, AccessRegistryUpgradeable.Status memory s, uint256 nonce, uint64 exp) internal view returns (AccessRegistryUpgradeable.StatusAttestation memory a) {
        a.subject = subject; a.s = s; a.nonce = nonce; a.issuedAt = uint64(block.timestamp); a.expiresAt = exp;
    }

    function _sign(AccessRegistryUpgradeable.StatusAttestation memory a) internal view returns (bytes memory sig) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("StatusAttestation(address subject,(bool kyc,bool kyb,bool accredited,bool pep,bool sanctioned,uint8 riskTier,uint16 countryISO,uint64 expiresAt,bytes32 metadataCid) s,uint256 nonce,uint64 issuedAt,uint64 expiresAt)"),
                a.subject,
                keccak256(abi.encode(
                    keccak256("Status(bool kyc,bool kyb,bool accredited,bool pep,bool sanctioned,uint8 riskTier,uint16 countryISO,uint64 expiresAt,bytes32 metadataCid)"),
                    a.s.kyc, a.s.kyb, a.s.accredited, a.s.pep, a.s.sanctioned, a.s.riskTier, a.s.countryISO, a.s.expiresAt, a.s.metadataCid
                )),
                a.nonce, a.issuedAt, a.expiresAt
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", reg.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 t) = vm.sign(0xC0DE, digest);
        sig = abi.encodePacked(r, t, v);
    }

    function testAttestBySig_and_Gate() public {
        address user = address(0x1234);
        AccessRegistryUpgradeable.Status memory s;
        s.kyc = true; s.kyb = false; s.accredited = true; s.riskTier = 3; s.countryISO = 840; s.expiresAt = uint64(block.timestamp + 30 days);
        AccessRegistryUpgradeable.StatusAttestation memory a = _att(user, s, 0, uint64(block.timestamp + 1 days));
        bytes memory sig = _sign(a);

        vm.prank(user); // caller can be anyone; registry verifies signer authority
        reg.attestBySig(a, sig);

        bool ok = reg.check(user, AccessRegistryUpgradeable.Gate.PRIMARY_AP);
        assertTrue(ok, "AP gate failed");
    }

    function testReplayReverts() public {
        address user = address(0x5678);
        AccessRegistryUpgradeable.Status memory s; s.kyc = true; s.accredited = true; s.countryISO = 840; s.expiresAt = uint64(block.timestamp + 7 days);
        AccessRegistryUpgradeable.StatusAttestation memory a = _att(user, s, 0, uint64(block.timestamp + 1 days));
        bytes memory sig = _sign(a);
        reg.attestBySig(a, sig);
        vm.expectRevert(Errors.Replay.selector);
        reg.attestBySig(a, sig);
    }
}
