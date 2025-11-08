// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title RebasingShares (index-based ERC-20)
/// @notice Minimal ERC-20-compatible token with global index. Balances = shares * index / 1e18.
///         Transfers/mints/burns convert amount <-> shares at current index. Rebase updates the index.
contract RebasingShares is IERC20, AccessControl, Pausable {
    bytes32 public constant ADMIN_ROLE  = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    string public name;
    string public symbol;
    uint8  public constant decimals = 18;

    uint256 public index;      // 1e18 scalar (starts at 1e18)
    uint256 public totalShares; // sum of internal shares

    mapping(address => uint256) internal sharesOf;
    mapping(address => mapping(address => uint256)) internal _allowances;

    event Rebased(uint256 oldIndex, uint256 newIndex);

    constructor(address admin, string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
        index = 1e18;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }

    // ---------------- ERC20 view ----------------
    function totalSupply() public view returns (uint256) {
        return (totalShares * index) / 1e18;
    }

    function balanceOf(address owner) public view returns (uint256) {
        return (sharesOf[owner] * index) / 1e18;
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    // ---------------- helpers ----------------
    function _toShares(uint256 amount) internal view returns (uint256) {
        return amount == 0 ? 0 : (amount * 1e18) / index;
    }

    function _toAmount(uint256 shares) internal view returns (uint256) {
        return shares == 0 ? 0 : (shares * index) / 1e18;
    }

    // ---------------- ERC20 core ----------------
    function transfer(address to, uint256 amount) public whenNotPaused returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) public whenNotPaused returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public whenNotPaused returns (bool) {
        uint256 allowed = _allowances[from][msg.sender];
        require(allowed >= amount, "allowance");
        if (allowed != type(uint256).max) {
            _allowances[from][msg.sender] = allowed - amount;
            emit Approval(from, msg.sender, _allowances[from][msg.sender]);
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(to != address(0), "to");
        uint256 sh = _toShares(amount);
        require(sharesOf[from] >= sh, "balance");
        unchecked { sharesOf[from] -= sh; sharesOf[to] += sh; }
        emit Transfer(from, to, amount);
    }

    // ---------------- mint/burn ----------------
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) whenNotPaused {
        uint256 sh = _toShares(amount);
        totalShares += sh; sharesOf[to] += sh;
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) public onlyRole(MINTER_ROLE) whenNotPaused {
        uint256 sh = _toShares(amount);
        require(sharesOf[from] >= sh, "balance");
        unchecked { sharesOf[from] -= sh; totalShares -= sh; }
        emit Transfer(from, address(0), amount);
    }

    // ---------------- admin ----------------
    function rebase(uint256 newIndex) public onlyRole(ADMIN_ROLE) whenNotPaused {
        require(newIndex > 0, "idx");
        uint256 old = index; index = newIndex;
        emit Rebased(old, newIndex);
    }

    function pause() public onlyRole(ADMIN_ROLE) { _pause(); }
    function unpause() public onlyRole(ADMIN_ROLE) { _unpause(); }
}
