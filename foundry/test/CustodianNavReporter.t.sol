// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

interface IReporter {
    struct NAVReport {
        address vault;
        uint256 totalAssets;
        uint64 navTime;
        uint64 validUntil;
        uint256 nonce;
    }
    function setSigner(address signer, bool allowed) external;
    function submitSignedReport(NAVReport calldata r, bytes calldata sig) external;
}

contract MockVault {
    bytes32 public constant CUSTODIAN = keccak256("CUSTODIAN");
    uint256 public totalAssets;
    mapping(bytes32 => mapping(address => bool)) public roles;
    event Report(uint256 assets);
    function grantRole(bytes32 r, address a) external { roles[r][a] = true; }
    function report(uint256 newTotalAssets) external {
        require(roles[CUSTODIAN][msg.sender], "no_custodian");
        totalAssets = newTotalAssets;
        emit Report(newTotalAssets);
    }
}

contract CustodianNavReporter is Test {
    // Minimal interface to deployed real contract in your repo:
    IReporter reporter;
    MockVault vault;

    address gov = vm.addr(0xA11CE);
    address custodian = vm.addr(0xC0FfEE);

    function setUp() public {
        // Deploy mock reporter bytecode using your compiled artifact,
        // or inline a minimal reporter for test purposes.
        // Here we mock by deploying your compiled artifact at runtime:
        // For simplicity, we assume governance constructor param.
        // Append constructor args (governor) to the creation bytecode.
        bytes memory creation = vm.getCode("CustodianNavReporter.sol:CustodianNavReporter");
        bytes memory bytecode = abi.encodePacked(creation, abi.encode(gov));
        address rep;
        assembly {
            rep := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(rep != address(0), "deploy_failed");
        // If your reporter requires init, call it here via vm.prank(gov)

        reporter = IReporter(rep);
        vault = new MockVault();

        // Grant reporter the CUSTODIAN role on the vault
        vault.grantRole(vault.CUSTODIAN(), address(reporter));

        // Allow custodian signer
        vm.prank(gov);
        reporter.setSigner(custodian, true);
    }

    function test_submit_valid_nav() public {
        // Build EIP-712-like struct (the contract verifies domain internally)
        IReporter.NAVReport memory r = IReporter.NAVReport({
            vault: address(vault),
            totalAssets: 123_456_789,
            navTime: uint64(block.timestamp),
            validUntil: uint64(block.timestamp + 900),
            nonce: 1
        });

        // Compute EIP-712 digest expected by the contract:
        // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
        bytes32 EIP712DOMAIN_TYPEHASH = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
        // keccak256("NAVReport(address vault,uint256 totalAssets,uint64 navTime,uint64 validUntil,uint256 nonce)")
        bytes32 NAVREPORT_TYPEHASH = keccak256(
            "NAVReport(address vault,uint256 totalAssets,uint64 navTime,uint64 validUntil,uint256 nonce)"
        );

        bytes32 nameHash = keccak256(bytes("CustodianNavReporter"));
        bytes32 versionHash = keccak256(bytes("1"));
        bytes32 domainSeparator = keccak256(
            abi.encode(
                EIP712DOMAIN_TYPEHASH,
                nameHash,
                versionHash,
                block.chainid,
                address(reporter)
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(
                NAVREPORT_TYPEHASH,
                r.vault,
                r.totalAssets,
                r.navTime,
                r.validUntil,
                r.nonce
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        // Sign with the correct private key corresponding to `custodian`
        // (vm.addr(0xC0FfEE) -> private key 0xC0FfEE)
        (uint8 v, bytes32 s1, bytes32 s2) = vm.sign(0xC0FfEE, digest);
        bytes memory sig = abi.encodePacked(s1, s2, v);

        // Caller can be anyone; signature authorizes the action
        reporter.submitSignedReport(r, sig);

        assertEq(vault.totalAssets(), r.totalAssets, "totalAssets mismatch");
    }
}
