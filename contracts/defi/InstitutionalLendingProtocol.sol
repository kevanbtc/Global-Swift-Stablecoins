// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title InstitutionalLendingProtocol
 * @notice Advanced lending protocol for institutional borrowers and lenders
 * @dev Supports collateralized lending, credit scoring, and risk-adjusted pricing
 */
contract InstitutionalLendingProtocol is Ownable, ReentrancyGuard, Pausable {

    using SafeERC20 for IERC20;

    enum LoanStatus {
        PENDING,
        ACTIVE,
        DEFAULTED,
        REPAID,
        LIQUIDATED
    }

    enum CreditRating {
        AAA,    // Prime
        AA,     // High grade
        A,      // Upper medium
        BBB,    // Lower medium
        BB,     // Non-investment grade
        B,      // Highly speculative
        CCC,    // Substantial risk
        D       // In default
    }

    enum CollateralType {
        CASH,
        SECURITIES,
        REAL_ESTATE,
        COMMODITIES,
        DIGITAL_ASSETS,
        OTHER
    }

    struct LoanTerms {
        uint256 principal;
        uint256 interestRate;      // BPS (e.g., 500 = 5%)
        uint256 duration;          // Seconds
        uint256 collateralRatio;   // BPS (e.g., 15000 = 150%)
        CollateralType collateralType;
        address collateralToken;
        uint256 collateralAmount;
        uint256 originationFee;    // BPS
        uint256 lateFee;          // BPS
        bool isFixedRate;
        bool allowsRefinancing;
    }

    struct Loan {
        bytes32 loanId;
        address borrower;
        address lender;
        LoanTerms terms;
        LoanStatus status;
        uint256 startTime;
        uint256 endTime;
        uint256 lastPaymentTime;
        uint256 totalPaid;
        uint256 outstandingPrincipal;
        uint256 accruedInterest;
        CreditRating borrowerRating;
        bool isSecured;
        bytes32 collateralId;
    }

    struct CreditProfile {
        address borrower;
        CreditRating rating;
        uint256 creditScore;       // 300-850 scale
        uint256 totalBorrowed;
        uint256 totalRepaid;
        uint256 activeLoans;
        uint256 defaultedLoans;
        uint256 lastActivity;
        bool isBlacklisted;
        bytes32[] loanHistory;
    }

    struct LendingPool {
        address asset;
        uint256 totalSupplied;
        uint256 totalBorrowed;
        uint256 utilizationRate;   // BPS
        uint256 baseRate;         // BPS
        uint256 slope1;           // BPS per utilization point
        uint256 slope2;           // BPS per utilization point
        uint256 optimalUtilization; // BPS
        bool isActive;
    }

    // Storage
    mapping(bytes32 => Loan) public loans;
    mapping(address => CreditProfile) public creditProfiles;
    mapping(address => LendingPool) public lendingPools;
    mapping(address => uint256) public userBalances;
    mapping(address => mapping(address => uint256)) public allowances;

    // Global parameters
    uint256 public minLoanAmount = 100000 * 1e18;     // 100k units
    uint256 public maxLoanAmount = 100000000 * 1e18;  // 100M units
    uint256 public minCollateralRatio = 11000;        // 110%
    uint256 public maxLoanDuration = 365 days;
    uint256 public originationFeeBPS = 25;            // 0.25%
    uint256 public lateFeeBPS = 500;                  // 5%
    uint256 public liquidationBonusBPS = 500;         // 5%

    // Counters
    uint256 public totalLoans;
    uint256 public activeLoans;
    uint256 public defaultedLoans;

    // Events
    event LoanRequested(bytes32 indexed loanId, address indexed borrower, uint256 amount);
    event LoanFunded(bytes32 indexed loanId, address indexed lender);
    event LoanRepayment(bytes32 indexed loanId, uint256 amount);
    event LoanDefaulted(bytes32 indexed loanId);
    event LoanLiquidated(bytes32 indexed loanId, uint256 collateralRecovered);
    event CreditProfileUpdated(address indexed borrower, CreditRating rating);
    event LendingPoolUpdated(address indexed asset, uint256 utilizationRate);

    modifier validLoanAmount(uint256 _amount) {
        require(_amount >= minLoanAmount, "Loan amount too small");
        require(_amount <= maxLoanAmount, "Loan amount too large");
        _;
    }

    modifier validCollateralRatio(uint256 _ratio) {
        require(_ratio >= minCollateralRatio, "Collateral ratio too low");
        _;
    }

    modifier onlyActiveLoan(bytes32 _loanId) {
        require(loans[_loanId].status == LoanStatus.ACTIVE, "Loan not active");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Request a new loan
     */
    function requestLoan(
        address _asset,
        uint256 _amount,
        uint256 _duration,
        uint256 _collateralRatio,
        CollateralType _collateralType,
        address _collateralToken,
        uint256 _collateralAmount
    ) public whenNotPaused validLoanAmount(_amount) validCollateralRatio(_collateralRatio)
         returns (bytes32) {

        require(_duration <= maxLoanDuration, "Loan duration too long");
        require(lendingPools[_asset].isActive, "Lending pool not active");

        // Check borrower's credit profile
        CreditProfile storage profile = creditProfiles[msg.sender];
        require(!profile.isBlacklisted, "Borrower blacklisted");
        require(profile.activeLoans < 5, "Too many active loans");

        // Calculate interest rate based on credit profile
        uint256 interestRate = _calculateInterestRate(msg.sender, _amount, _duration);

        // Create loan terms
        LoanTerms memory terms = LoanTerms({
            principal: _amount,
            interestRate: interestRate,
            duration: _duration,
            collateralRatio: _collateralRatio,
            collateralType: _collateralType,
            collateralToken: _collateralToken,
            collateralAmount: _collateralAmount,
            originationFee: originationFeeBPS,
            lateFee: lateFeeBPS,
            isFixedRate: true,
            allowsRefinancing: true
        });

        bytes32 loanId = keccak256(abi.encodePacked(
            msg.sender,
            _asset,
            _amount,
            block.timestamp
        ));

        loans[loanId] = Loan({
            loanId: loanId,
            borrower: msg.sender,
            lender: address(0),
            terms: terms,
            status: LoanStatus.PENDING,
            startTime: 0,
            endTime: 0,
            lastPaymentTime: 0,
            totalPaid: 0,
            outstandingPrincipal: _amount,
            accruedInterest: 0,
            borrowerRating: profile.rating,
            isSecured: _collateralAmount > 0,
            collateralId: bytes32(0)
        });

        totalLoans++;
        profile.activeLoans++;

        emit LoanRequested(loanId, msg.sender, _amount);
        return loanId;
    }

    /**
     * @notice Fund a pending loan
     */
    function fundLoan(bytes32 _loanId) public whenNotPaused nonReentrant {
        Loan storage loan = loans[_loanId];
        require(loan.status == LoanStatus.PENDING, "Loan not pending");
        require(loan.borrower != msg.sender, "Cannot fund own loan");

        LendingPool storage pool = lendingPools[loan.terms.collateralToken];
        require(pool.totalSupplied >= loan.terms.principal, "Insufficient pool liquidity");

        // Transfer collateral from borrower
        if (loan.isSecured) {
            IERC20(loan.terms.collateralToken).safeTransferFrom(
                loan.borrower,
                address(this),
                loan.terms.collateralAmount
            );
        }

        // Transfer principal to borrower
        IERC20(loan.terms.collateralToken).safeTransfer(loan.borrower, loan.terms.principal);

        // Update loan status
        loan.lender = msg.sender;
        loan.status = LoanStatus.ACTIVE;
        loan.startTime = block.timestamp;
        loan.endTime = block.timestamp + loan.terms.duration;

        // Update pool
        pool.totalBorrowed += loan.terms.principal;
        pool.utilizationRate = (pool.totalBorrowed * 10000) / pool.totalSupplied;

        activeLoans++;

        emit LoanFunded(_loanId, msg.sender);
    }

    /**
     * @notice Make a loan repayment
     */
    function repayLoan(bytes32 _loanId, uint256 _amount) public onlyActiveLoan(_loanId)
        nonReentrant
    {
        Loan storage loan = loans[_loanId];
        require(msg.sender == loan.borrower, "Not loan borrower");

        // Calculate accrued interest
        uint256 interestDue = _calculateAccruedInterest(_loanId);
        uint256 totalDue = loan.outstandingPrincipal + interestDue;

        require(_amount <= totalDue, "Repayment amount too high");

        // Transfer payment
        IERC20(loan.terms.collateralToken).safeTransferFrom(msg.sender, address(this), _amount);

        loan.totalPaid += _amount;
        loan.lastPaymentTime = block.timestamp;

        // Apply payment to interest first, then principal
        if (_amount <= interestDue) {
            loan.accruedInterest -= _amount;
        } else {
            loan.accruedInterest = 0;
            loan.outstandingPrincipal -= (_amount - interestDue);
        }

        // Check if loan is fully repaid
        if (loan.outstandingPrincipal == 0) {
            loan.status = LoanStatus.REPAID;

            // Return collateral
            if (loan.isSecured) {
                IERC20(loan.terms.collateralToken).safeTransfer(
                    loan.borrower,
                    loan.terms.collateralAmount
                );
            }

            activeLoans--;
            creditProfiles[loan.borrower].activeLoans--;
        }

        emit LoanRepayment(_loanId, _amount);
    }

    /**
     * @notice Liquidate a defaulted loan
     */
    function liquidateLoan(bytes32 _loanId) public onlyActiveLoan(_loanId) nonReentrant {
        Loan storage loan = loans[_loanId];

        // Check if loan is past due
        require(block.timestamp > loan.endTime, "Loan not past due");

        // Check if collateral value covers outstanding amount
        uint256 outstandingAmount = loan.outstandingPrincipal + loan.accruedInterest;
        uint256 collateralValue = _getCollateralValue(loan.terms.collateralToken, loan.terms.collateralAmount);

        require(collateralValue >= outstandingAmount, "Insufficient collateral");

        // Calculate liquidation bonus
        uint256 liquidationAmount = outstandingAmount + (outstandingAmount * liquidationBonusBPS / 10000);

        // Transfer collateral to liquidator
        IERC20(loan.terms.collateralToken).safeTransfer(msg.sender, loan.terms.collateralAmount);

        loan.status = LoanStatus.LIQUIDATED;
        activeLoans--;
        defaultedLoans++;

        // Update credit profile
        CreditProfile storage profile = creditProfiles[loan.borrower];
        profile.defaultedLoans++;
        profile.activeLoans--;

        emit LoanLiquidated(_loanId, loan.terms.collateralAmount);
    }

    /**
     * @notice Update credit profile
     */
    function updateCreditProfile(
        address _borrower,
        CreditRating _rating,
        uint256 _creditScore
    ) public onlyOwner {
        require(_creditScore >= 300 && _creditScore <= 850, "Invalid credit score");

        CreditProfile storage profile = creditProfiles[_borrower];
        profile.rating = _rating;
        profile.creditScore = _creditScore;
        profile.lastActivity = block.timestamp;

        emit CreditProfileUpdated(_borrower, _rating);
    }

    /**
     * @notice Create or update a lending pool
     */
    function updateLendingPool(
        address _asset,
        uint256 _baseRate,
        uint256 _slope1,
        uint256 _slope2,
        uint256 _optimalUtilization
    ) public onlyOwner {
        lendingPools[_asset] = LendingPool({
            asset: _asset,
            totalSupplied: 0,
            totalBorrowed: 0,
            utilizationRate: 0,
            baseRate: _baseRate,
            slope1: _slope1,
            slope2: _slope2,
            optimalUtilization: _optimalUtilization,
            isActive: true
        });

        emit LendingPoolUpdated(_asset, 0);
    }

    /**
     * @notice Deposit to lending pool
     */
    function depositToPool(address _asset, uint256 _amount) public whenNotPaused nonReentrant {
        require(lendingPools[_asset].isActive, "Pool not active");

        IERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount);

        LendingPool storage pool = lendingPools[_asset];
        pool.totalSupplied += _amount;

        userBalances[msg.sender] += _amount;

        pool.utilizationRate = pool.totalBorrowed > 0 ?
            (pool.totalBorrowed * 10000) / pool.totalSupplied : 0;

        emit LendingPoolUpdated(_asset, pool.utilizationRate);
    }

    /**
     * @notice Withdraw from lending pool
     */
    function withdrawFromPool(address _asset, uint256 _amount) public nonReentrant {
        require(userBalances[msg.sender] >= _amount, "Insufficient balance");

        LendingPool storage pool = lendingPools[_asset];
        require(pool.totalSupplied - pool.totalBorrowed >= _amount, "Insufficient liquidity");

        pool.totalSupplied -= _amount;
        userBalances[msg.sender] -= _amount;

        IERC20(_asset).safeTransfer(msg.sender, _amount);

        pool.utilizationRate = pool.totalBorrowed > 0 ?
            (pool.totalBorrowed * 10000) / pool.totalSupplied : 0;

        emit LendingPoolUpdated(_asset, pool.utilizationRate);
    }

    /**
     * @notice Get loan details
     */
    function getLoan(bytes32 _loanId) public view
        returns (
            address borrower,
            address lender,
            LoanStatus status,
            uint256 outstandingPrincipal,
            uint256 accruedInterest,
            uint256 endTime
        )
    {
        Loan memory loan = loans[_loanId];
        return (
            loan.borrower,
            loan.lender,
            loan.status,
            loan.outstandingPrincipal,
            loan.accruedInterest,
            loan.endTime
        );
    }

    /**
     * @notice Get credit profile
     */
    function getCreditProfile(address _borrower) public view
        returns (
            CreditRating rating,
            uint256 creditScore,
            uint256 activeLoans,
            uint256 defaultedLoans,
            bool isBlacklisted
        )
    {
        CreditProfile memory profile = creditProfiles[_borrower];
        return (
            profile.rating,
            profile.creditScore,
            profile.activeLoans,
            profile.defaultedLoans,
            profile.isBlacklisted
        );
    }

    /**
     * @notice Update protocol parameters
     */
    function updateParameters(
        uint256 _minLoanAmount,
        uint256 _maxLoanAmount,
        uint256 _minCollateralRatio,
        uint256 _originationFeeBPS,
        uint256 _lateFeeBPS
    ) public onlyOwner {
        minLoanAmount = _minLoanAmount;
        maxLoanAmount = _maxLoanAmount;
        minCollateralRatio = _minCollateralRatio;
        originationFeeBPS = _originationFeeBPS;
        lateFeeBPS = _lateFeeBPS;
    }

    /**
     * @notice Emergency pause
     */
    function emergencyPause() public onlyOwner {
        _pause();
    }

    /**
     * @notice Emergency unpause
     */
    function emergencyUnpause() public onlyOwner {
        _unpause();
    }

    // Internal functions

    function _calculateInterestRate(
        address _borrower,
        uint256 _amount,
        uint256 _duration
    ) internal view returns (uint256) {
        CreditProfile memory profile = creditProfiles[_borrower];

        // Base rate based on credit rating
        uint256 baseRate;
        if (profile.rating == CreditRating.AAA) baseRate = 300;      // 3%
        else if (profile.rating == CreditRating.AA) baseRate = 400;  // 4%
        else if (profile.rating == CreditRating.A) baseRate = 500;   // 5%
        else if (profile.rating == CreditRating.BBB) baseRate = 600; // 6%
        else if (profile.rating == CreditRating.BB) baseRate = 800;  // 8%
        else if (profile.rating == CreditRating.B) baseRate = 1200;  // 12%
        else baseRate = 2000; // 20%

        // Adjust for loan size (larger loans get better rates)
        if (_amount > 10000000 * 1e18) { // 10M+
            baseRate = baseRate * 95 / 100; // 5% discount
        }

        // Adjust for duration (longer terms get higher rates)
        if (_duration > 180 days) {
            baseRate = baseRate * 110 / 100; // 10% premium
        }

        return baseRate;
    }

    function _calculateAccruedInterest(bytes32 _loanId) internal view returns (uint256) {
        Loan memory loan = loans[_loanId];

        if (loan.status != LoanStatus.ACTIVE) return 0;

        uint256 timeElapsed = block.timestamp - loan.lastPaymentTime;
        uint256 interestAccrued = (loan.outstandingPrincipal * loan.terms.interestRate * timeElapsed) /
                                  (365 days * 10000);

        return loan.accruedInterest + interestAccrued;
    }

    function _getCollateralValue(address _token, uint256 _amount) internal view returns (uint256) {
        // Simplified - in production would query price oracle
        return _amount; // Assume 1:1 for now
    }
}
