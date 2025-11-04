// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IRiskWeights} from "../interfaces/ExternalInterfaces.sol";
contract RiskWeightsMock is IRiskWeights { mapping(address=>uint16) public w; function set(address a, uint16 bps) external { w[a]=bps; } function weightOf(address a) external view returns (uint16){ return w[a]; } }
