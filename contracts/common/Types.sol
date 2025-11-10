// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

library Types {
    enum Jurisdiction { US, EU, UK, SG, AE, CH, OTHER }
    enum InvestorClass { RETAIL, ACCREDITED, INSTITUTIONAL, RESTRICTED }
    enum KYCState { NONE, PENDING, APPROVED, REVOKED, SANCTIONED }

    struct AccountStatus {
        KYCState kyc;
        Jurisdiction juris;
        InvestorClass klass;
        uint64 reviewedAt;
        uint64 lockupEnd;        // unix, per-account lockup
        bool frozen;             // per-account freeze toggle
    }

    // Policy inputs passed by the token into the PolicyEngine
    struct TransferContext {
        address token;
        address operator;
        address from;
        address to;
        uint256 amount;
    }

    // Besu-specific types for Unykorn L1 integration
    enum BesuPermission { NONE, NODE, ADMIN }
    struct BesuNode {
        address nodeAddress;
        BesuPermission permission;
        bytes32 privacyGroup;  // For Besu privacy features
    }

    // SWIFT GPI status for tracking
    enum SWIFTStatus { PENDING, ACCEPTED, REJECTED, COMPLETED }
    struct SWIFTTracking {
        string uetr;  // Unique End-to-End Reference
        SWIFTStatus status;
        uint256 timestamp;
    }

    enum AssetId {
        USDC,
        USDT,
        TGUSD,
        FTHUSD,
        RLUSD
    }
}
