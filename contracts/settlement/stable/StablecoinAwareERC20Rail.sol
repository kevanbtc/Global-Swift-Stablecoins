// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRail} from "../rails/IRail.sol";
import {IReleaseGuard} from "./IReleaseGuard.sol";

interface IERC20 { function transferFrom(address, address, uint256) external returns (bool); function transfer(address, uint256) external returns (bool); }

/// @title StablecoinAwareERC20Rail
/// @notice ERC20 rail with an optional release guard (e.g., PoR, policy, sanctions) checked before release
contract StablecoinAwareERC20Rail is IRail {
    address public admin;
    IReleaseGuard public guard; // optional; if unset, releases proceed unguarded

    mapping(bytes32 => Status) private _status;

    modifier onlyAdmin(){ require(msg.sender==admin, "R20G: not admin"); _; }
    constructor(address _admin, address _guard){ require(_admin!=address(0), "R20G: 0"); admin=_admin; guard = IReleaseGuard(_guard); }

    function setGuard(address g) external onlyAdmin { guard = IReleaseGuard(g); }

    function kind() external pure override returns (Kind){ return Kind.ERC20; }

    function transferId(Transfer calldata t) public pure returns (bytes32){
        return keccak256(abi.encode("R20G", t.asset, t.from, t.to, t.amount, t.metadata));
    }

    function prepare(Transfer calldata t) external payable override {
        require(t.asset != address(0), "R20G: asset 0");
        bytes32 id = transferId(t);
        require(_status[id] == Status.NONE, "R20G: exists");
        require(IERC20(t.asset).transferFrom(t.from, address(this), t.amount), "R20G: pull fail");
        _status[id] = Status.PREPARED;
        emit RailPrepared(id, t.from, t.to, t.asset, t.amount);
    }

    function release(bytes32 id, Transfer calldata t) external override onlyAdmin {
        require(_status[id] == Status.PREPARED, "R20G: bad state");
        if (address(guard) != address(0)) {
            (bool ok,) = guard.canRelease(t.asset, t.to, t.amount);
            require(ok, "R20G: guard");
        }
        _status[id] = Status.RELEASED;
        require(IERC20(t.asset).transfer(t.to, t.amount), "R20G: xfer fail");
        emit RailReleased(id, t.to, t.asset, t.amount);
    }

    function refund(bytes32 id, Transfer calldata t) external override onlyAdmin {
        require(_status[id] == Status.PREPARED, "R20G: bad state");
        _status[id] = Status.REFUNDED;
        require(IERC20(t.asset).transfer(t.from, t.amount), "R20G: refund fail");
        emit RailRefunded(id, t.from, t.asset, t.amount);
    }

    function status(bytes32 id) external view override returns (Status){ return _status[id]; }
}
