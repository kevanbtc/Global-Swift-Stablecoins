// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// This file intentionally imports OpenZeppelin's TimelockController so Hardhat generates its artifact,
// allowing scripts to obtain a ContractFactory via ethers.getContractFactory("TimelockController").
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";

// No additional code is needed here.
