// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ExternalRailEIP712} from "../../../contracts/settlement/rails/ExternalRailEIP712.sol";
import {IRail} from "../../../contracts/settlement/rails/IRail.sol";

contract ExternalRailEIP712Test is Test {
    address admin = address(0xA11CE);
    uint256 signerPk = 0xBEEF;
    address signer;

    function setUp() public {
        signer = vm.addr(signerPk);
    }

    function _sig(ExternalRailEIP712 rail, bytes32 id, bool released, uint64 settledAt) internal view returns (bytes memory) {
        bytes32 digest = rail.hashReceipt(id, released, settledAt);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_MarksReleased_with_valid_signature() public {
        ExternalRailEIP712 rail = new ExternalRailEIP712(admin);
        vm.prank(admin); rail.setSigner(signer, true);

        IRail.Transfer memory t = IRail.Transfer({
            asset: address(0),
            from: address(0x1),
            to: address(0x2),
            amount: 100,
            metadata: bytes("bank-route-abc")
        });

        rail.prepare(t);
        bytes32 id = rail.transferId(t);
        uint64 settledAt = uint64(block.timestamp);
        bytes memory sig = _sig(rail, id, true, settledAt);

        rail.markWithReceipt(t, true, settledAt, sig);
        assertEq(uint(rail.status(id)), uint(IRail.Status.RELEASED));
    }

    function test_Reverts_with_bad_signer() public {
        ExternalRailEIP712 rail = new ExternalRailEIP712(admin);
        // signer not set

        IRail.Transfer memory t = IRail.Transfer({
            asset: address(0),
            from: address(0x1),
            to: address(0x2),
            amount: 100,
            metadata: bytes("route")
        });
        rail.prepare(t);
        bytes32 id = rail.transferId(t);
        bytes memory sig = _sig(rail, id, true, uint64(block.timestamp));

        vm.expectRevert("X712: bad signer");
        rail.markWithReceipt(t, true, uint64(block.timestamp), sig);
    }
}
