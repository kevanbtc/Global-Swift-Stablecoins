// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable as AC} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

interface IERC20 { function transfer(address to, uint256 amt) external returns (bool); }

contract MerkleStreamDistributorUpgradeable is Initializable, AC {
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    struct Epoch {
        bytes32 root;
        IERC20  token;
        uint64  start;
        uint64  end;
        uint256 total;
        bool    active;
    }

    mapping(uint256 => mapping(uint256 => uint256)) public claimed; // epoch => index => cumulative
    mapping(uint256 => Epoch) public epochs;
    uint256 public epochCount;

    event EpochCreated(uint256 indexed id, bytes32 root, address token, uint64 start, uint64 end, uint256 total);
    event Claimed(uint256 indexed id, uint256 indexed index, address indexed account, uint256 amount, uint256 cumulative);

    function initialize(address admin, address governor) public initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GOVERNOR_ROLE, governor);
    }

    function createEpoch(bytes32 root, address token, uint64 start, uint64 end, uint256 total)
        external onlyRole(GOVERNOR_ROLE) returns (uint256 id)
    {
        require(end > start, "time");
        id = ++epochCount;
        epochs[id] = Epoch({root: root, token: IERC20(token), start: start, end: end, total: total, active: true});
        emit EpochCreated(id, root, token, start, end, total);
    }

    function vested(uint256 id, uint256 totalAmount) public view returns (uint256 v) {
        Epoch memory e = epochs[id];
        if (block.timestamp <= e.start) return 0;
        if (block.timestamp >= e.end) return totalAmount;
        v = (totalAmount * (block.timestamp - e.start)) / (e.end - e.start);
    }

    function claim(uint256 id, uint256 index, address account, uint256 totalAmount, bytes32[] calldata proof) external {
        Epoch memory e = epochs[id];
        require(e.active && e.root != 0, "epoch");
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(index, account, totalAmount))));
        require(MerkleProof.verify(proof, e.root, leaf), "proof");

        uint256 allowed = vested(id, totalAmount);
        uint256 already = claimed[id][index];
        require(allowed > already, "nothing");

        uint256 pay = allowed - already;
        claimed[id][index] = allowed;
        require(e.token.transfer(account, pay), "transfer");
        emit Claimed(id, index, account, pay, allowed);
    }
}
