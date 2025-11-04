// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {IRail} from "../../../contracts/settlement/rails/IRail.sol";
import {ERC20Rail} from "../../../contracts/settlement/rails/ERC20Rail.sol";
import {ExternalRail} from "../../../contracts/settlement/rails/ExternalRail.sol";
import {RailRegistry} from "../../../contracts/settlement/rails/RailRegistry.sol";

import {StablecoinAwareERC20Rail} from "../../../contracts/settlement/stable/StablecoinAwareERC20Rail.sol";
import {StablecoinRegistry} from "../../../contracts/settlement/stable/StablecoinRegistry.sol";
import {PoRGuard} from "../../../contracts/settlement/stable/PoRGuard.sol";
import {CCTPExternalRail} from "../../../contracts/settlement/stable/CCTPExternalRail.sol";
import {CCIPRail} from "../../../contracts/settlement/stable/CCIPRail.sol";
import {StablecoinRouter} from "../../../contracts/settlement/stable/StablecoinRouter.sol";
import {IProofOfReserves} from "../../../contracts/interfaces/IProofOfReserves.sol";

contract MockPOR is IProofOfReserves {
    bool public allow = true;
    function set(bool a) external { allow = a; }
    function checkMint(bytes32, uint256) external view returns (bool) { return allow; }
    function checkRedeem(bytes32, uint256) external view returns (bool) { return allow; }
}

contract MockERC20 {
    string public name = "Mock";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function mint(address to, uint256 amount) external {
        totalSupply += amount; balanceOf[to] += amount; emit Transfer(address(0), to, amount);
    }
    function approve(address spender, uint256 amount) external returns (bool){ allowance[msg.sender][spender] = amount; emit Approval(msg.sender, spender, amount); return true; }
    function transfer(address to, uint256 amount) external returns (bool){ _transfer(msg.sender, to, amount); return true; }
    function transferFrom(address from, address to, uint256 amount) external returns (bool){ uint256 a = allowance[from][msg.sender]; require(a >= amount, "allowance"); if (a != type(uint256).max) { allowance[from][msg.sender] = a - amount; } _transfer(from, to, amount); return true; }
    function _transfer(address from, address to, uint256 amount) internal { require(balanceOf[from] >= amount, "balance"); balanceOf[from] -= amount; balanceOf[to] += amount; emit Transfer(from, to, amount); }
}

contract StableRailsTest is Test {
    address admin = address(0xA11CE);
    address exec  = address(0xE1);
    address user  = address(this);

    function test_PoRGuard_blocks_release_when_denied() public {
        // Token + balances
        MockERC20 token = new MockERC20();
        token.mint(user, 1_000 ether);

        // Registry + POR guard (deny)
        StablecoinRegistry reg = new StablecoinRegistry(admin);
        MockPOR por = new MockPOR(); por.set(false);
        PoRGuard guard = new PoRGuard(address(reg));
        vm.prank(admin);
        reg.setStablecoin(address(token), true, bytes32("TGUSD"), address(por), 0, bytes32(0), bytes32(0), bytes32(0));

        // Guarded rail
        StablecoinAwareERC20Rail rail = new StablecoinAwareERC20Rail(admin, address(guard));

        // Approve rail to pull from user (this test contract)
        token.approve(address(rail), 100 ether);

        IRail.Transfer memory t = IRail.Transfer({
            asset: address(token),
            from: user,
            to: address(0xBEEF),
            amount: 100 ether,
            metadata: bytes("")
        });

        rail.prepare(t);
        bytes32 tid = rail.transferId(t);
        assertEq(uint(rail.status(tid)), uint(IRail.Status.PREPARED));

        // Admin attempts release -> should revert due to guard
        vm.prank(admin);
        vm.expectRevert("R20G: guard");
        rail.release(tid, t);
    }

    function test_Router_routes_prepare_to_ERC20Rail() public {
        // Setup registry and rails
        RailRegistry registry = new RailRegistry(admin);
        ERC20Rail erc20Rail = new ERC20Rail(admin);

        bytes32 KEY = keccak256("ERC20_RAIL");
        vm.prank(admin);
        registry.set(KEY, address(erc20Rail));

        // Router config
        StablecoinRouter router = new StablecoinRouter(admin, address(registry));

        // Token + balances
        MockERC20 token = new MockERC20();
        token.mint(user, 1_000 ether);
        token.approve(address(erc20Rail), 50 ether);

        // Set default rail for token
        vm.prank(admin);
        router.setDefaultRail(address(token), KEY);

        IRail.Transfer memory t = IRail.Transfer({
            asset: address(token),
            from: user,
            to: address(0xCAFE),
            amount: 50 ether,
            metadata: bytes("")
        });

        bytes32 tid = router.routeAndPrepare(t);

        // Verify status prepared in ERC20 rail and balances moved
        assertEq(uint(erc20Rail.status(tid)), uint(IRail.Status.PREPARED));
        assertEq(token.balanceOf(address(erc20Rail)), 50 ether);
    }

    function test_CCTP_and_CCIP_exec_mark_release() public {
        CCTPExternalRail cctp = new CCTPExternalRail(admin, exec, 0);
        CCIPRail ccip = new CCIPRail(admin, exec);

        IRail.Transfer memory t = IRail.Transfer({
            asset: address(0),
            from: address(0x1),
            to: address(0x2),
            amount: 123,
            metadata: bytes("note")
        });

        cctp.prepare(t);
        ccip.prepare(t);
        bytes32 id1 = cctp.transferId(t);
        bytes32 id2 = ccip.transferId(t);
        assertEq(uint(cctp.status(id1)), uint(IRail.Status.PREPARED));
        assertEq(uint(ccip.status(id2)), uint(IRail.Status.PREPARED));

        // Only executor may mark released
        vm.expectRevert("CCTP: not exec"); cctp.markReleased(id1, t);
        vm.expectRevert("CCIP: not exec"); ccip.markReleased(id2, t);

        vm.prank(exec); cctp.markReleased(id1, t);
        vm.prank(exec); ccip.markReleased(id2, t);
        assertEq(uint(cctp.status(id1)), uint(IRail.Status.RELEASED));
        assertEq(uint(ccip.status(id2)), uint(IRail.Status.RELEASED));
    }
}
