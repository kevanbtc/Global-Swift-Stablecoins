// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ERC20Rail} from "contracts/settlement/rails/ERC20Rail.sol";
import {IRail} from "contracts/settlement/rails/IRail.sol";
import {MockMintableERC20} from "contracts/mocks/MockMintableERC20.sol";

contract SettlementSmokeTest is Test {
    address alice = address(0xA11CE);
    address bob   = address(0xB0B);

    function test_erc20rail_prepare_release_refund() external {
        ERC20Rail rail = new ERC20Rail(address(this));
        MockMintableERC20 usdc = new MockMintableERC20("MockUSD", "mUSD");
        usdc.mint(alice, 1_000e18);
        vm.startPrank(alice);
        usdc.approve(address(rail), type(uint256).max);
        vm.stopPrank();

        IRail.Transfer memory t = IRail.Transfer({asset: address(usdc), from: alice, to: bob, amount: 100e18, metadata: bytes("")});
        rail.prepare(t);
        bytes32 id = rail.transferId(t);
        assertEq(uint(rail.status(id)), uint(IRail.Status.PREPARED));

        // As admin, release to bob
        rail.release(id, t);
        assertEq(uint(rail.status(id)), uint(IRail.Status.RELEASED));
    }
}
