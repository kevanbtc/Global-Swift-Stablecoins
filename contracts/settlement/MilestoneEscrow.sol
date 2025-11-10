// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20Pay { function transferFrom(address from, address to, uint256 value) external returns (bool); function transfer(address to, uint256 value) external returns (bool); }

/**
 * @title MilestoneEscrow
 * @notice Multi-milestone escrow with dual-approval and deadline/expiry, payable in an ERC20.
 */
contract MilestoneEscrow {
    address public admin;

    struct Milestone { uint256 amount; bool buyerApproved; bool sellerApproved; bool released; }

    address public buyer;
    address public seller;
    address public token;      // ERC20 used for payment
    uint64  public deadline;   // escrow expiry

    Milestone[] public milestones;
    uint256 public funded;     // total funded so far

    event AdminTransferred(address indexed from, address indexed to);
    event Funded(address indexed from, uint256 amount);
    event Approved(uint256 indexed idx, address indexed by, bool buyerApproved, bool sellerApproved);
    event Released(uint256 indexed idx, uint256 amount);
    event Refunded(uint256 amount);

    modifier onlyAdmin() { require(msg.sender == admin, "ME: not admin"); _; }
    modifier onlyBuyer() { require(msg.sender == buyer, "ME: not buyer"); _; }

    constructor(address _admin, address _buyer, address _seller, address _token, uint64 _deadline, uint256[] memory amounts) {
        require(_admin!=address(0) && _buyer!=address(0) && _seller!=address(0) && _token!=address(0), "ME: 0 addr");
        admin = _admin; buyer = _buyer; seller = _seller; token = _token; deadline = _deadline;
        for (uint256 i=0;i<amounts.length;i++){ milestones.push(Milestone({amount: amounts[i], buyerApproved:false, sellerApproved:false, released:false})); }
    }

    function transferAdmin(address to) public onlyAdmin { require(to!=address(0), "ME: 0"); emit AdminTransferred(admin,to); admin = to; }

    function fund(uint256 amount) public onlyBuyer { require(IERC20Pay(token).transferFrom(msg.sender, address(this), amount), "ME: fund fail"); funded += amount; emit Funded(msg.sender, amount); }

    function approve(uint256 idx) public { require(idx < milestones.length, "ME: idx"); if (msg.sender == buyer) milestones[idx].buyerApproved = true; else if (msg.sender == seller) milestones[idx].sellerApproved = true; else revert("ME: no auth"); emit Approved(idx, msg.sender, milestones[idx].buyerApproved, milestones[idx].sellerApproved); }

    function release(uint256 idx, address to) public onlyAdmin {
        require(block.timestamp <= deadline, "ME: expired"); Milestone storage m = milestones[idx]; require(!m.released && m.buyerApproved && m.sellerApproved, "ME: not releasable"); require(funded >= m.amount, "ME: unfunded"); m.released = true; funded -= m.amount; require(IERC20Pay(token).transfer(to, m.amount), "ME: xfer fail"); emit Released(idx, m.amount);
    }

    function refundRemaining(address to) public onlyAdmin { uint256 bal = funded; funded = 0; require(IERC20Pay(token).transfer(to, bal), "ME: refund fail"); emit Refunded(bal); }
}
