// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IProofOfReserves} from "../../interfaces/IProofOfReserves.sol";
import {StablecoinRegistry} from "./StablecoinRegistry.sol";
import {IReleaseGuard} from "./IReleaseGuard.sol";

/// @title PoRGuard
/// @notice Release guard that checks a token's Proof-of-Reserves policy via StablecoinRegistry
contract PoRGuard is IReleaseGuard {
    StablecoinRegistry public immutable registry;

    constructor(address _registry){ require(_registry!=address(0), "PORG: 0"); registry = StablecoinRegistry(_registry); }

    function canRelease(address token, address /*to*/, uint256 amount) external view override returns (bool ok, bytes memory reason){
        StablecoinRegistry.Meta memory m = registry.get(token);
        // If not listed or no PoR adapter, do not block
        if (!m.supported || m.por == address(0)) {
            return (true, bytes("no-por"));
        }
        // Use checkRedeem as a conservative guard for outbound releases
        bool allowed = IProofOfReserves(m.por).checkRedeem(m.reserveId, amount);
        if (!allowed) {
            return (false, bytes("por-deny"));
        }
        return (true, bytes("ok"));
    }
}
