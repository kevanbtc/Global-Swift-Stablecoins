// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
contract PriceOracleMock is IPriceOracle {
    mapping(address => uint256) public price; // 1e18
    function set(address asset, uint256 p) external { price[asset] = p; }
    function priceE18(address asset) external view returns (uint256 p, uint64 ts) { p = price[asset]; ts = uint64(block.timestamp); }
}
