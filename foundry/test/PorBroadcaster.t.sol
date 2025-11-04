// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../contracts/ccip/PorBroadcaster.sol";
import "../../contracts/common/Errors.sol";

contract ReserveMock is IReserveQuorumView {
    Snapshot s;
    uint64 e;
    function set(uint64 _e, Snapshot memory _s) external { e=_e; s=_s; }
    function latestSealed() external view returns (uint64 epoch, Snapshot memory _s) { return (e, s); }
}
contract RouterMock is IRouterClient {
    uint256 public lastFee;
    bytes public lastMsg;
    function getFee(uint64, Client.EVM2AnyMessage calldata) external view returns (uint256){ return lastFee; }
    function ccipSend(uint64, Client.EVM2AnyMessage calldata message) external payable returns (bytes32){
        lastMsg = message.data; return keccak256("sent");
    }
    function setFee(uint256 f) external { lastFee = f; }
}

contract PorBroadcasterTest is Test {
    ReserveMock res;
    RouterMock  rc;
    PorBroadcaster br;
    address gov = address(0xBEEF);

    function setUp() public {
        res = new ReserveMock();
        rc  = new RouterMock();
        br  = new PorBroadcaster(address(rc), address(res), gov);
        IReserveQuorumView.Snapshot memory s;
        s.totalAssets1e18 = 10_000e18; s.asOf = uint64(block.timestamp);
        res.set(uint64(block.timestamp/1 days), s);
        rc.setFee(1 ether);
        vm.deal(gov, 10 ether);
    }

    function testBroadcastPaysFee() public {
        vm.prank(gov);
        br.broadcast{value: 1 ether}(101, address(0xDEAD));
        // success if no revert; deeper assertions could parse lastMsg
    }

    function testBroadcastInsufficientFee() public {
        vm.prank(gov);
        vm.expectRevert(Errors.InvalidParam.selector);
        br.broadcast{value: 0.5 ether}(101, address(0xDEAD));
    }
}
