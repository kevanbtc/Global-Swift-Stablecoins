// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Upgradeable} from "../IERC20Upgradeable.sol";

library SafeERC20Upgradeable {
    using SafeERC20 for IERC20;

    function safeTransfer(IERC20Upgradeable token, address to, uint256 value) internal {
        SafeERC20.safeTransfer(IERC20(address(token)), to, value);
    }

    function safeTransferFrom(IERC20Upgradeable token, address from, address to, uint256 value) internal {
        SafeERC20.safeTransferFrom(IERC20(address(token)), from, to, value);
    }

    function safeApprove(IERC20Upgradeable token, address spender, uint256 value) internal {
        SafeERC20.forceApprove(IERC20(address(token)), spender, value);
    }

    function safeIncreaseAllowance(IERC20Upgradeable token, address spender, uint256 value) internal {
        SafeERC20.safeIncreaseAllowance(IERC20(address(token)), spender, value);
    }

    function safeDecreaseAllowance(IERC20Upgradeable token, address spender, uint256 value) internal {
        SafeERC20.safeDecreaseAllowance(IERC20(address(token)), spender, value);
    }
}
