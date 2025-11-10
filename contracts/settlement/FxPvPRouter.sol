// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRail} from "./rails/IRail.sol";
import {IPriceOracle} from "../oracle/IPriceOracle.sol";

/**
 * @title FxPvPRouter
 * @notice Price‑checked PvP for two ERC‑20 tokens on the same chain with slippage control. Escrow via an ERC20-compatible rail.
 */
contract FxPvPRouter {
    address public admin;
    IPriceOracle public oracle;
    IRail public erc20Rail;

    event AdminTransferred(address indexed from, address indexed to);

    modifier onlyAdmin(){ require(msg.sender==admin, "FX: not admin"); _; }

    constructor(address _admin, address _oracle, address _erc20Rail){
        require(_admin!=address(0) && _oracle!=address(0) && _erc20Rail!=address(0), "FX: 0");
        admin=_admin; oracle=IPriceOracle(_oracle); erc20Rail=IRail(_erc20Rail);
    }

    function transferAdmin(address to) public onlyAdmin { require(to!=address(0), "FX: 0"); emit AdminTransferred(admin,to); admin=to; }

    /// @notice Prepare both sides with price bound (using USD or shared quote from oracle).
    function prepareBound(
        IRail.Transfer calldata legA,
        IRail.Transfer calldata legB,
        uint256 maxSlippageBps // allowed deviation from oracle-implied amount
    ) public onlyAdmin {
        require(legA.asset != address(0) && legB.asset != address(0), "FX: assets");
        (uint256 pA, uint8 dA) = oracle.getPrice(legA.asset);
        (uint256 pB, uint8 dB) = oracle.getPrice(legB.asset);
        // Value in a common numeraire (e.g., USD with dA/dB decimals)
        // valueA = amtA * pA / 10^dA ; expected amtB = valueA * 10^dB / pB
        uint256 valueA = (legA.amount * pA) / (10 ** dA);
        uint256 impliedB = (valueA * (10 ** dB)) / pB;
        uint256 lower = (impliedB * (10_000 - maxSlippageBps)) / 10_000;
        uint256 upper = (impliedB * (10_000 + maxSlippageBps)) / 10_000;
        require(legB.amount >= lower && legB.amount <= upper, "FX: slippage");
        erc20Rail.prepare(legA);
        erc20Rail.prepare(legB);
    }
}
