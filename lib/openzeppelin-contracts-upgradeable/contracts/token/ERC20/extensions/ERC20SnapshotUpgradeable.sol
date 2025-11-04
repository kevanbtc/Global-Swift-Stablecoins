// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Minimal compatibility stub for OZ v5 where ERC20SnapshotUpgradeable is not present.
// This stub provides init, a dummy _snapshot, and passes through _update.

import {Initializable} from "../../../proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "../ERC20Upgradeable.sol";

abstract contract ERC20SnapshotUpgradeable is Initializable, ERC20Upgradeable {
    event Snapshot(uint256 id);

    function __ERC20Snapshot_init() internal onlyInitializing {}
    function __ERC20Snapshot_init_unchained() internal onlyInitializing {}

    function _snapshot() internal virtual returns (uint256 id) {
        // Dummy snapshot id (use block number). Replace with full snapshot logic if needed.
        id = block.number;
        emit Snapshot(id);
    }

    function _update(address from, address to, uint256 value)
        internal
        virtual
        override(ERC20Upgradeable)
    {
        super._update(from, to, value);
    }
}