// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title WrappedShares4626
/// @notice Non-rebasing ERC4626 wrapper over a (potentially rebasing) ERC20 asset.
///         If the asset balance of this vault increases (e.g., due to rebase), share price rises.
contract WrappedShares4626 is ERC20, ERC4626, AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    constructor(IERC20 asset_, string memory name_, string memory symbol_, address admin)
        ERC20(name_, symbol_)
        ERC4626(asset_)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
    }

    function decimals() public view override(ERC20, ERC4626) returns (uint8) {
        return ERC4626.decimals();
    }
}
