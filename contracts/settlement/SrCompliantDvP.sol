// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface IERC20 { function transfer(address to, uint256 value) external returns (bool); function transferFrom(address from, address to, uint256 value) external returns (bool); }
interface IERC20Permit { function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external; }
interface IERC721 { function transferFrom(address from, address to, uint256 tokenId) external; function isApprovedForAll(address owner, address operator) external view returns (bool); function getApproved(uint256 tokenId) external view returns (address); }
interface IERC1155 { function isApprovedForAll(address account, address operator) external view returns (bool); function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data) external; }

interface IComplianceGate { function check(address from, address to, address asset, uint256 amount, bytes calldata context) external view returns (bool ok, bytes memory reason); }
interface ISanctionsOracle { function isSanctioned(address account) external view returns (bool); }

contract SrCompliantDvP is Initializable, ReentrancyGuardUpgradeable, PausableUpgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    bytes32 public constant PAUSER_ROLE  = keccak256("PAUSER_ROLE");
    bytes32 public constant SETTLER_ROLE = keccak256("SETTLER_ROLE");

    enum Kind { PVP_ERC20, DVP_ERC721_FOR_ERC20, DVP_ERC1155_FOR_ERC20 }
    enum State { Open, Funded, Settled, Cancelled, Expired }

    struct FeeCfg { uint16 bps; address recipient; }
    FeeCfg public fee;

    IComplianceGate public compliance;
    ISanctionsOracle public sanctions;

    struct IsoRefs { bytes16 uetr; bytes32 e2eIdHash; bytes32 isoPayloadHash; }

    struct PvP20 { address partyA; address tokenA; uint256 amtA; address partyB; address tokenB; uint256 amtB; }
    struct DvP721 { address seller; address nft; uint256 tokenId; address buyer; address payToken; uint256 price; }
    struct DvP1155 { address seller; address nft; uint256 tokenId; uint256 amount; address buyer; address payToken; uint256 price; }

    struct Instruction {
        Kind kind; State state; uint64 createdAt; uint64 deadline; IsoRefs iso; bytes complianceCtx;
        bool erc20FundedSideA; bool erc20FundedSideB; bool nftEscrowed;
        PvP20 pvp; DvP721 dvp721; DvP1155 dvp1155;
    }

    mapping(bytes32 => Instruction) public instructions;

    event InstructionCreated(bytes32 indexed id, Kind kind, bytes16 uetr, address indexed creator, uint64 deadline);
    event IsoRefsUpdated(bytes32 indexed id, bytes16 uetr, bytes32 e2eIdHash, bytes32 isoPayloadHash);
    event FundedERC20(bytes32 indexed id, address indexed from, address indexed token, uint256 amount, bool sideA);
    event EscrowedERC721(bytes32 indexed id, address indexed from, address indexed nft, uint256 tokenId);
    event EscrowedERC1155(bytes32 indexed id, address indexed from, address indexed nft, uint256 tokenId, uint256 amount);
    event Settled(bytes32 indexed id, bytes16 uetr, address indexed by);
    event Cancelled(bytes32 indexed id, address indexed by, State reason);
    event FeeUpdated(uint16 bps, address recipient);
    event ComplianceModuleUpdated(address module);
    event SanctionsOracleUpdated(address oracle);

    modifier onlyExisting(bytes32 id) { require(instructions[id].createdAt != 0, "SR: unknown id"); _; }

    function initialize(address admin, address _compliance, address _sanctions, uint16 feeBps, address feeRecipient) public initializer {
        __ReentrancyGuard_init(); __Pausable_init(); __AccessControl_init(); __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin); _grantRole(PAUSER_ROLE, admin); _grantRole(SETTLER_ROLE, admin);
        if (_compliance != address(0)) compliance = IComplianceGate(_compliance);
        if (_sanctions != address(0))  sanctions  = ISanctionsOracle(_sanctions);
        _setFee(feeBps, feeRecipient);
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function pause() public onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() public onlyRole(PAUSER_ROLE) { _unpause(); }

    function setComplianceModule(address m) public onlyRole(DEFAULT_ADMIN_ROLE) { compliance = IComplianceGate(m); emit ComplianceModuleUpdated(m); }
    function setSanctionsOracle(address o) public onlyRole(DEFAULT_ADMIN_ROLE) { sanctions = ISanctionsOracle(o); emit SanctionsOracleUpdated(o); }
    function setFee(uint16 bps, address recipient) public onlyRole(DEFAULT_ADMIN_ROLE) { _setFee(bps, recipient); }
    function _setFee(uint16 bps, address recipient) internal { require(bps <= 2000, "SR: fee high"); require(recipient != address(0), "SR: fee to"); fee = FeeCfg({bps: bps, recipient: recipient}); emit FeeUpdated(bps, recipient); }

    function createPvP20(bytes32 id, IsoRefs calldata isoRefs, address partyA, address tokenA, uint256 amtA, address partyB, address tokenB, uint256 amtB, uint64 deadline, bytes calldata complianceCtx) public whenNotPaused nonReentrant onlyRole(SETTLER_ROLE) {
        require(instructions[id].createdAt == 0, "SR: id exists"); _sanctionsCheck(partyA); _sanctionsCheck(partyB);
        Instruction storage ins = instructions[id];
        ins.kind = Kind.PVP_ERC20; ins.state = State.Open; ins.createdAt = uint64(block.timestamp); ins.deadline = deadline; ins.iso = isoRefs; ins.complianceCtx = complianceCtx;
        ins.pvp = PvP20({ partyA: partyA, tokenA: tokenA, amtA: amtA, partyB: partyB, tokenB: tokenB, amtB: amtB });
        emit InstructionCreated(id, Kind.PVP_ERC20, isoRefs.uetr, msg.sender, deadline);
        emit IsoRefsUpdated(id, isoRefs.uetr, isoRefs.e2eIdHash, isoRefs.isoPayloadHash);
    }

    function createDvP721(bytes32 id, IsoRefs calldata isoRefs, address seller, address nft, uint256 tokenId, address buyer, address payToken, uint256 price, uint64 deadline, bytes calldata complianceCtx) public whenNotPaused nonReentrant onlyRole(SETTLER_ROLE) {
        require(instructions[id].createdAt == 0, "SR: id exists"); _sanctionsCheck(seller); _sanctionsCheck(buyer);
        Instruction storage ins = instructions[id];
        ins.kind = Kind.DVP_ERC721_FOR_ERC20; ins.state = State.Open; ins.createdAt = uint64(block.timestamp); ins.deadline = deadline; ins.iso = isoRefs; ins.complianceCtx = complianceCtx;
        ins.dvp721 = DvP721({ seller: seller, nft: nft, tokenId: tokenId, buyer: buyer, payToken: payToken, price: price });
        emit InstructionCreated(id, Kind.DVP_ERC721_FOR_ERC20, isoRefs.uetr, msg.sender, deadline);
        emit IsoRefsUpdated(id, isoRefs.uetr, isoRefs.e2eIdHash, isoRefs.isoPayloadHash);
    }

    function createDvP1155(bytes32 id, IsoRefs calldata isoRefs, address seller, address nft, uint256 tokenId, uint256 amount, address buyer, address payToken, uint256 price, uint64 deadline, bytes calldata complianceCtx) public whenNotPaused nonReentrant onlyRole(SETTLER_ROLE) {
        require(instructions[id].createdAt == 0, "SR: id exists"); _sanctionsCheck(seller); _sanctionsCheck(buyer);
        Instruction storage ins = instructions[id];
        ins.kind = Kind.DVP_ERC1155_FOR_ERC20; ins.state = State.Open; ins.createdAt = uint64(block.timestamp); ins.deadline = deadline; ins.iso = isoRefs; ins.complianceCtx = complianceCtx;
        ins.dvp1155 = DvP1155({ seller: seller, nft: nft, tokenId: tokenId, amount: amount, buyer: buyer, payToken: payToken, price: price });
        emit InstructionCreated(id, Kind.DVP_ERC1155_FOR_ERC20, isoRefs.uetr, msg.sender, deadline);
        emit IsoRefsUpdated(id, isoRefs.uetr, isoRefs.e2eIdHash, isoRefs.isoPayloadHash);
    }

    function fundErc20(bytes32 id, uint256 amount, bool sideA) public nonReentrant whenNotPaused onlyExisting(id) {
        Instruction storage ins = instructions[id]; _requireOpen(ins);
        if (ins.kind == Kind.PVP_ERC20) {
            if (sideA) { require(msg.sender == ins.pvp.partyA, "SR: not A"); require(amount == ins.pvp.amtA, "SR: amtA"); _preflightCompliance(msg.sender, ins.pvp.partyB, ins.pvp.tokenA, amount, ins.complianceCtx); require(IERC20(ins.pvp.tokenA).transferFrom(msg.sender, address(this), amount), "SR: xferFrom A"); ins.erc20FundedSideA = true; emit FundedERC20(id, msg.sender, ins.pvp.tokenA, amount, true); }
            else { require(msg.sender == ins.pvp.partyB, "SR: not B"); require(amount == ins.pvp.amtB, "SR: amtB"); _preflightCompliance(msg.sender, ins.pvp.partyA, ins.pvp.tokenB, amount, ins.complianceCtx); require(IERC20(ins.pvp.tokenB).transferFrom(msg.sender, address(this), amount), "SR: xferFrom B"); ins.erc20FundedSideB = true; emit FundedERC20(id, msg.sender, ins.pvp.tokenB, amount, false); }
        } else if (ins.kind == Kind.DVP_ERC721_FOR_ERC20) {
            require(msg.sender == ins.dvp721.buyer, "SR: not buyer"); require(amount == ins.dvp721.price, "SR: price"); _preflightCompliance(msg.sender, ins.dvp721.seller, ins.dvp721.payToken, amount, ins.complianceCtx); require(IERC20(ins.dvp721.payToken).transferFrom(msg.sender, address(this), amount), "SR: xferFrom pay"); ins.erc20FundedSideA = true; emit FundedERC20(id, msg.sender, ins.dvp721.payToken, amount, true);
        } else {
            require(msg.sender == ins.dvp1155.buyer, "SR: not buyer"); require(amount == ins.dvp1155.price, "SR: price"); _preflightCompliance(msg.sender, ins.dvp1155.seller, ins.dvp1155.payToken, amount, ins.complianceCtx); require(IERC20(ins.dvp1155.payToken).transferFrom(msg.sender, address(this), amount), "SR: xferFrom pay"); ins.erc20FundedSideA = true; emit FundedERC20(id, msg.sender, ins.dvp1155.payToken, amount, true);
        }
    }

    function fundErc20WithPermit(bytes32 id, bool sideA, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) public nonReentrant whenNotPaused onlyExisting(id) {
        Instruction storage ins = instructions[id]; address token; address owner;
        if (ins.kind == Kind.PVP_ERC20) { if (sideA) { token = ins.pvp.tokenA; owner = ins.pvp.partyA; require(owner == msg.sender, "SR: not A"); } else { token = ins.pvp.tokenB; owner = ins.pvp.partyB; require(owner == msg.sender, "SR: not B"); } }
        else if (ins.kind == Kind.DVP_ERC721_FOR_ERC20) { token = ins.dvp721.payToken; owner = ins.dvp721.buyer; require(owner == msg.sender, "SR: not buyer"); }
        else { token = ins.dvp1155.payToken; owner = ins.dvp1155.buyer; require(owner == msg.sender, "SR: not buyer"); }
        IERC20Permit(token).permit(owner, address(this), amount, deadline, v, r, s); fundErc20(id, amount, sideA);
    }

    function depositERC721(bytes32 id) public nonReentrant whenNotPaused onlyExisting(id) {
        Instruction storage ins = instructions[id]; _requireOpen(ins); require(ins.kind == Kind.DVP_ERC721_FOR_ERC20, "SR: not 721"); require(msg.sender == ins.dvp721.seller, "SR: not seller");
        _preflightCompliance(msg.sender, ins.dvp721.buyer, ins.dvp721.nft, 1, ins.complianceCtx);
        address nft = ins.dvp721.nft; uint256 tid = ins.dvp721.tokenId; require(_isNftApprovedFor(address(this), nft, msg.sender, tid), "SR: approve NFT first");
        IERC721(nft).transferFrom(msg.sender, address(this), tid); ins.nftEscrowed = true; emit EscrowedERC721(id, msg.sender, nft, tid);
    }

    function depositERC1155(bytes32 id) public nonReentrant whenNotPaused onlyExisting(id) {
        Instruction storage ins = instructions[id]; _requireOpen(ins); require(ins.kind == Kind.DVP_ERC1155_FOR_ERC20, "SR: not 1155"); require(msg.sender == ins.dvp1155.seller, "SR: not seller");
        _preflightCompliance(msg.sender, ins.dvp1155.buyer, ins.dvp1155.nft, ins.dvp1155.amount, ins.complianceCtx);
        IERC1155(ins.dvp1155.nft).safeTransferFrom(msg.sender, address(this), ins.dvp1155.tokenId, ins.dvp1155.amount, ""); ins.nftEscrowed = true; emit EscrowedERC1155(id, msg.sender, ins.dvp1155.nft, ins.dvp1155.tokenId, ins.dvp1155.amount);
    }

    function settle(bytes32 id) public nonReentrant whenNotPaused onlyExisting(id) {
        Instruction storage ins = instructions[id]; _requireOpen(ins); require(block.timestamp <= ins.deadline, "SR: expired");
        if (ins.kind == Kind.PVP_ERC20) { require(ins.erc20FundedSideA && ins.erc20FundedSideB, "SR: fund both"); _payoutERC20(ins.pvp.tokenA, ins.pvp.partyB, ins.pvp.amtA); _payoutERC20(ins.pvp.tokenB, ins.pvp.partyA, ins.pvp.amtB); }
        else if (ins.kind == Kind.DVP_ERC721_FOR_ERC20) { require(ins.erc20FundedSideA && ins.nftEscrowed, "SR: not funded"); IERC721(ins.dvp721.nft).transferFrom(address(this), ins.dvp721.buyer, ins.dvp721.tokenId); _payoutERC20(ins.dvp721.payToken, ins.dvp721.seller, ins.dvp721.price); }
        else { require(ins.erc20FundedSideA && ins.nftEscrowed, "SR: not funded"); IERC1155(ins.dvp1155.nft).safeTransferFrom(address(this), ins.dvp1155.buyer, ins.dvp1155.tokenId, ins.dvp1155.amount, ""); _payoutERC20(ins.dvp1155.payToken, ins.dvp1155.seller, ins.dvp1155.price); }
        ins.state = State.Settled; emit Settled(id, ins.iso.uetr, msg.sender);
    }

    function cancel(bytes32 id) public nonReentrant whenNotPaused onlyExisting(id) {
        Instruction storage ins = instructions[id]; require(ins.state == State.Open, "SR: not open"); bool admin = hasRole(DEFAULT_ADMIN_ROLE, msg.sender) || hasRole(SETTLER_ROLE, msg.sender); bool byParty = _isParty(ins, msg.sender); require(admin || byParty || block.timestamp > ins.deadline, "SR: no cancel");
        if (ins.kind == Kind.PVP_ERC20) { if (ins.erc20FundedSideA) { IERC20(ins.pvp.tokenA).transfer(ins.pvp.partyA, ins.pvp.amtA); } if (ins.erc20FundedSideB) { IERC20(ins.pvp.tokenB).transfer(ins.pvp.partyB, ins.pvp.amtB); } }
        else if (ins.kind == Kind.DVP_ERC721_FOR_ERC20) { if (ins.erc20FundedSideA) { IERC20(ins.dvp721.payToken).transfer(ins.dvp721.buyer, ins.dvp721.price); } if (ins.nftEscrowed) { IERC721(ins.dvp721.nft).transferFrom(address(this), ins.dvp721.seller, ins.dvp721.tokenId); } }
        else { if (ins.erc20FundedSideA) { IERC20(ins.dvp1155.payToken).transfer(ins.dvp1155.buyer, ins.dvp1155.price); } if (ins.nftEscrowed) { IERC1155(ins.dvp1155.nft).safeTransferFrom(address(this), ins.dvp1155.seller, ins.dvp1155.tokenId, ins.dvp1155.amount, ""); } }
        ins.state = (block.timestamp > ins.deadline) ? State.Expired : State.Cancelled; emit Cancelled(id, msg.sender, ins.state);
    }

    function updateIsoRefs(bytes32 id, IsoRefs calldata isoRefs) public onlyRole(SETTLER_ROLE) onlyExisting(id) { Instruction storage ins = instructions[id]; require(ins.state == State.Open, "SR: locked"); ins.iso = isoRefs; emit IsoRefsUpdated(id, isoRefs.uetr, isoRefs.e2eIdHash, isoRefs.isoPayloadHash); }

    function _preflightCompliance(address from, address to, address asset, uint256 amount, bytes memory ctx) internal view {
        _sanctionsCheck(from); _sanctionsCheck(to);
        if (address(compliance) != address(0)) { (bool ok, bytes memory reason) = compliance.check(from, to, asset, amount, ctx); require(ok, reason.length > 0 ? string(reason) : "SR: compliance"); }
    }
    function _sanctionsCheck(address a) internal view { if (address(sanctions) != address(0)) { require(!sanctions.isSanctioned(a), "SR: sanctioned"); } }

    function _payoutERC20(address token, address to, uint256 gross) internal { if (fee.bps > 0 && fee.recipient != address(0)) { uint256 cut = (gross * fee.bps) / 10_000; if (cut > 0) { require(IERC20(token).transfer(fee.recipient, cut), "SR: fee xfer"); } require(IERC20(token).transfer(to, gross - cut), "SR: payout"); } else { require(IERC20(token).transfer(to, gross), "SR: payout"); } }

    function _requireOpen(Instruction storage ins) internal view { require(ins.state == State.Open, "SR: not open"); }
    function _isParty(Instruction storage ins, address who) internal view returns (bool) {
        if (ins.kind == Kind.PVP_ERC20) { return (who == ins.pvp.partyA || who == ins.pvp.partyB); }
        else if (ins.kind == Kind.DVP_ERC721_FOR_ERC20) { return (who == ins.dvp721.seller || who == ins.dvp721.buyer); }
        else { return (who == ins.dvp1155.seller || who == ins.dvp1155.buyer); }
    }

    function _isNftApprovedFor(address operator, address nft, address owner, uint256 tokenId) internal view returns (bool) {
        try IERC721(nft).getApproved(tokenId) returns (address a) { if (a == operator) return true; } catch {}
        try IERC721(nft).isApprovedForAll(owner, operator) returns (bool all) { if (all) return true; } catch {}
        return false;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) public pure returns (bytes4) { return this.onERC1155Received.selector; }
    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) public pure returns (bytes4) { return this.onERC1155BatchReceived.selector; }
}
