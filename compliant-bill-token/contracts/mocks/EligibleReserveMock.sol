// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IEligibleReserve} from "../interfaces/ExternalInterfaces.sol";
contract EligibleReserveMock is IEligibleReserve { uint256 public val; function set(uint256 v) external { val=v; } function eligibleValueUSD() external view returns (uint256){ return val; } }
