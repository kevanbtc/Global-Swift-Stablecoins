// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockMintableERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    uint256 public override totalSupply;
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    constructor(string memory n, string memory s) { name = n; symbol = s; }

    function mint(address to, uint256 amount) external {
        totalSupply += amount; balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "bal");
        balanceOf[msg.sender] -= amount; balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 a = allowance[from][msg.sender];
        require(a >= amount, "allow");
        if (a != type(uint256).max) { allowance[from][msg.sender] = a - amount; emit Approval(from, msg.sender, allowance[from][msg.sender]); }
        require(balanceOf[from] >= amount, "bal");
        balanceOf[from] -= amount; balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}
