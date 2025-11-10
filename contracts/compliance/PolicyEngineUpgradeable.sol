// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable as AC} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Types} from "../common/Types.sol";
import {CustomErrors} from "../common/Errors.sol";

interface ICourtOrderRegistry {
    function globalFreeze(address token) external view returns (bool);
    // For gas reasons we require the token/controller to pass the active order id if needed.
    function isActive(bytes32 orderId) external view returns (bool);
}

interface IComplianceRegistry {
    function sanctioned(address) external view returns (bool);
    function getStatus(address) external view returns (Types.AccountStatus memory);
}

contract PolicyEngineUpgradeable is Initializable, AC {
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    bytes32 public constant WRITER_ROLE   = keccak256("WRITER_ROLE");

    IComplianceRegistry public registry;
    ICourtOrderRegistry public court;

    // Global policy switches
    bool public globalPaused;
    bool public requireKYCApproved;
    bool public restrictJurisdictionUSOnly;
    uint256 public maxHolderBalance; // 0 = off
    uint256 public maxDailyOutflow;  // 0 = off

    // per-account last spent (very simple rate limiter; extend as needed)
    mapping(address => uint256) public lastOutflowTs;
    mapping(address => uint256) public lastOutflowAmt;

    event PolicySet(bytes32 key, bytes value);
    event RegistriesSet(address registry, address court);

    function initialize(address admin, address governor, address registry_, address court_) public initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GOVERNOR_ROLE, governor);
        registry = IComplianceRegistry(registry_);
        court = ICourtOrderRegistry(court_);
        emit RegistriesSet(registry_, court_);
        requireKYCApproved = true;
    }

    function setSwitches(
        bool _globalPaused,
        bool _requireKYCApproved,
        bool _restrictUSOnly
    ) public onlyRole(GOVERNOR_ROLE) {
        globalPaused = _globalPaused;
        requireKYCApproved = _requireKYCApproved;
        restrictJurisdictionUSOnly = _restrictUSOnly;
        emit PolicySet("switches", abi.encode(_globalPaused, _requireKYCApproved, _restrictUSOnly));
    }

    function setCaps(uint256 _maxHolderBalance, uint256 _maxDailyOutflow) public onlyRole(GOVERNOR_ROLE) {
        maxHolderBalance = _maxHolderBalance;
        maxDailyOutflow = _maxDailyOutflow;
        emit PolicySet("caps", abi.encode(_maxHolderBalance, _maxDailyOutflow));
    }

    /// @notice Primary transfer gate. Reverts on violations.
    function checkTransfer(Types.TransferContext calldata ctx) public view {
        if (globalPaused) revert CustomErrors.GlobalPause();
        if (court.globalFreeze(ctx.token)) revert CustomErrors.Frozen();

        if (registry.sanctioned(ctx.from) || registry.sanctioned(ctx.to)) revert CustomErrors.Sanctioned();

        Types.AccountStatus memory sf = registry.getStatus(ctx.from);
        Types.AccountStatus memory st = registry.getStatus(ctx.to);

        if (requireKYCApproved) {
            if (sf.kyc != Types.KYCState.APPROVED || st.kyc != Types.KYCState.APPROVED) revert CustomErrors.AttestationInvalid();
        }
        if (sf.frozen || st.frozen) revert CustomErrors.Frozen();
        if (block.timestamp < sf.lockupEnd) revert CustomErrors.LockupActive();

        if (restrictJurisdictionUSOnly) {
            if (sf.juris != Types.Jurisdiction.US || st.juris != Types.Jurisdiction.US) revert CustomErrors.JurisdictionBlocked();
        }
        // investor class example: disallow RETAIL as recipient
        if (st.klass == Types.InvestorClass.RESTRICTED) revert CustomErrors.InvestorClassBlocked();

        // balance/outflow caps are enforced in token by reading this state;
        // (here we only centralize logic flags and per-account stats)
    }
}
