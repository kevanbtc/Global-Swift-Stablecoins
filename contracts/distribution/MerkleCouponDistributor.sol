// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

interface IComplianceRegistry {
    function isCompliant(address who) external view returns (bool);
}

/// @title MerkleCouponDistributor
/// @notice Pays coupon/dividend entitlements using a Merkle tree computed from a partition snapshot.
contract MerkleCouponDistributor is AccessControl, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant ROLE_ADMIN    = keccak256("ROLE_ADMIN");
    bytes32 public constant ROLE_MANAGER  = keccak256("ROLE_MANAGER"); // create distributions, fund, sweep

    struct Distribution {
        IERC20  asset;          // payout token
        bytes32 partition;      // partition this distribution pertains to (informational)
        bytes32 merkleRoot;     // merkle root of (index, account, amount)
        uint256 totalAmount;    // total amount earmarked
        uint256 claimedAmount;  // running total claimed
        uint64  createdAt;      // unix
        uint64  deadline;       // unix (0 = no deadline)
        bool    active;         // guard
        string  uri;            // IPFS / HTTPS metadata (CSV + JSON)
    }

    // distributionId => Distribution
    mapping(uint256 => Distribution) public dists;
    // distributionId => claimed bitmap
    mapping(uint256 => mapping(uint256 => uint256)) private _claimedBitMap;

    IComplianceRegistry public compliance; // optional
    uint256 public lastId;

    event DistributionCreated(
        uint256 indexed id,
        address indexed asset,
        bytes32 indexed partition,
        bytes32 merkleRoot,
        uint256 totalAmount,
        uint64 deadline,
        string uri
    );
    event Claimed(uint256 indexed id, uint256 indexed index, address indexed account, uint256 amount);
    event Swept(uint256 indexed id, address to, uint256 amount);
    event ComplianceSet(address registry);
    event Paused();
    event Unpaused();

    constructor(address admin, IComplianceRegistry reg) {
        _grantRole(ROLE_ADMIN, admin);
        _grantRole(ROLE_MANAGER, admin);
        compliance = reg;
    }

    // ---------- Admin ----------
    function setCompliance(IComplianceRegistry reg) external onlyRole(ROLE_ADMIN) {
        compliance = reg;
        emit ComplianceSet(address(reg));
    }

    function pause() external onlyRole(ROLE_ADMIN) { _pause(); emit Paused(); }
    function unpause() external onlyRole(ROLE_ADMIN) { _unpause(); emit Unpaused(); }

    // ---------- Distribution lifecycle ----------
    function createDistribution(
        IERC20 asset,
        bytes32 partition,
        bytes32 merkleRoot,
        uint256 totalAmount,
        uint64 deadline,
        string calldata uri,
        address fundFrom
    ) external onlyRole(ROLE_MANAGER) whenNotPaused returns (uint256 id) {
        require(address(asset) != address(0), "asset=0");
        require(merkleRoot != bytes32(0), "root=0");
        require(totalAmount > 0, "amount=0");

        id = ++lastId;
        Distribution storage d = dists[id];
        d.asset = asset;
        d.partition = partition;
        d.merkleRoot = merkleRoot;
        d.totalAmount = totalAmount;
        d.createdAt = uint64(block.timestamp);
        d.deadline = deadline;
        d.active = true;
        d.uri = uri;

        if (fundFrom != address(0)) {
            asset.safeTransferFrom(fundFrom, address(this), totalAmount);
        }

        emit DistributionCreated(id, address(asset), partition, merkleRoot, totalAmount, deadline, uri);
    }

    function sweep(uint256 id, address to) external onlyRole(ROLE_MANAGER) whenNotPaused {
        Distribution storage d = dists[id];
        require(d.active, "inactive");
        if (d.deadline != 0) require(block.timestamp > d.deadline, "not expired");
        uint256 remaining = d.totalAmount - d.claimedAmount;
        d.active = false; // prevent further claiming
        if (remaining > 0) {
            d.asset.safeTransfer(to, remaining);
            emit Swept(id, to, remaining);
        }
    }

    // ---------- Claiming ----------
    function isClaimed(uint256 id, uint256 index) public view returns (bool) {
        uint256 wordIndex = index >> 8;        // /256
        uint256 bitIndex  = index & 0xff;      // %256
        uint256 word = _claimedBitMap[id][wordIndex];
        uint256 mask = (1 << bitIndex);
        return (word & mask) != 0;
    }

    function _setClaimed(uint256 id, uint256 index) private {
        uint256 wordIndex = index >> 8;
        uint256 bitIndex  = index & 0xff;
        _claimedBitMap[id][wordIndex] |= (1 << bitIndex);
    }

    /// @notice Claim your entitlement.
    /// @param id Distribution id.
    /// @param index Leaf index used in Merkle tree.
    /// @param account Claiming address.
    /// @param amount Entitled amount.
    /// @param merkleProof Proof from leaf to root.
    function claim(
        uint256 id,
        uint256 index,
        address account,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external whenNotPaused {
        Distribution storage d = dists[id];
        require(d.active, "inactive");
        if (d.deadline != 0) require(block.timestamp <= d.deadline, "expired");
        require(!isClaimed(id, index), "claimed");

        if (address(compliance) != address(0)) {
            require(compliance.isCompliant(account), "compliance");
        }

        // Verify leaf
        bytes32 node = keccak256(bytes.concat(keccak256(abi.encode(index, account, amount))));
        require(MerkleProof.verify(merkleProof, d.merkleRoot, node), "bad proof");

        _setClaimed(id, index);
        d.claimedAmount += amount;
        d.asset.safeTransfer(account, amount);

        emit Claimed(id, index, account, amount);
    }
}
