// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

// NOTE: Snapshot extension is unavailable in the current OZ v5 libs in this repo.
// This placeholder keeps the symbol around for code that references it, without
// introducing a dependency on ERC20Snapshot.

import {RWASecurityToken} from "./RWASecurityToken.sol";
import {IComplianceRegistry} from "../interfaces/IComplianceRegistry.sol";

contract RWASecurityTokenSnapshot is RWASecurityToken {
    constructor(
        string memory name_,
        string memory symbol_,
        address admin,
        IComplianceRegistry reg,
        bytes32 partition
    ) RWASecurityToken(name_, symbol_, admin, reg, partition) {}
}
