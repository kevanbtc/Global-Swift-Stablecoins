// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IReserveOracle} from "../interfaces/ExternalInterfaces.sol";
contract ReserveOracleMock is IReserveOracle {
    bool public fresh = true; uint256 public nav; uint256 public liab;
    function set(uint256 _nav, uint256 _liab, bool _fresh) external { nav = _nav; liab = _liab; fresh = _fresh; }
    function isFresh() external view returns (bool) { return fresh; }
    function navUSD() external view returns (uint256) { return nav; }
    function liabilitiesUSD() external view returns (uint256) { return liab; }
}
