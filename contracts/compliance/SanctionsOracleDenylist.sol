// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title SanctionsOracleDenylist
 * @notice Simple on-chain denylist; production deployments typically proxy to an off-chain intel provider.
 */
contract SanctionsOracleDenylist {
    address public admin;
    mapping(address => bool) private _list;

    event AdminTransferred(address indexed from, address indexed to);
    event SanctionSet(address indexed account, bool flagged);

    modifier onlyAdmin() { require(msg.sender == admin, "SO: not admin"); _; }
    constructor(address _admin) { require(_admin != address(0), "SO: admin 0"); admin = _admin; }

    function transferAdmin(address to) external onlyAdmin { require(to != address(0), "SO: 0"); emit AdminTransferred(admin, to); admin = to; }

    function isSanctioned(address a) external view returns (bool) { return _list[a]; }

    function set(address a, bool flagged) external onlyAdmin { _list[a] = flagged; emit SanctionSet(a, flagged); }
}
