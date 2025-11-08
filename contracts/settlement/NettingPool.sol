// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20Minimal { function transferFrom(address from, address to, uint256 value) external returns (bool); }

/**
 * @title NettingPool
 * @notice Simple bilateral execution pool for ERC20 obligations. For small batches this executes pairwise transfers.
 */
contract NettingPool {
    address public admin;

    struct Obligation { address from; address to; uint256 amount; }
    // token => list of obligations for current round
    mapping(address => Obligation[]) public obls;

    event AdminTransferred(address indexed from, address indexed to);
    event ObligationAdded(address indexed token, address indexed from, address indexed to, uint256 amount);
    event Settled(address indexed token);

    modifier onlyAdmin() { require(msg.sender == admin, "NP: not admin"); _; }
    constructor(address _admin) { require(_admin != address(0), "NP: admin 0"); admin = _admin; }

    function transferAdmin(address to) public onlyAdmin { require(to != address(0), "NP: 0"); emit AdminTransferred(admin, to); admin = to; }

    function addObligation(address token, address from, address to, uint256 amount) public onlyAdmin {
        require(amount > 0, "NP: amt 0"); require(from != to, "NP: same");
        obls[token].push(Obligation({from: from, to: to, amount: amount}));
        emit ObligationAdded(token, from, to, amount);
    }

    function settle(address token) public onlyAdmin {
        Obligation[] storage L = obls[token];
        for (uint256 i=0; i<L.length; i++) {
            IERC20Minimal(token).transferFrom(L[i].from, L[i].to, L[i].amount);
        }
        delete obls[token];
        emit Settled(token);
    }
}
