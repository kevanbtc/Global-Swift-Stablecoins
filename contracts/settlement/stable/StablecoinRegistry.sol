// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title StablecoinRegistry
/// @notice Minimal registry of third-party stablecoin metadata and preferred rails
contract StablecoinRegistry {
    address public admin;

    struct Meta {
        bool    supported;         // listed in the registry
        bytes32  reserveId;         // identifier used with PoR oracle/manager
        address  por;               // IProofOfReserves-compat contract
        uint16   minReserveRatioBps;// optional floor, if applicable to in-house tokens
        bytes32  defaultRailKey;    // preferred same-chain rail key (in RailRegistry)
        bytes32  cctpRailKey;       // USDC CCTP rail (if configured)
        bytes32  ccipRailKey;       // CCIP rail (if configured)
    }

    mapping(address => Meta) private _meta; // token => metadata

    event AdminTransferred(address indexed from, address indexed to);
    event StablecoinSet(address indexed token, Meta meta);

    modifier onlyAdmin(){ require(msg.sender == admin, "SCREG: not admin"); _; }

    constructor(address _admin){ require(_admin!=address(0), "SCREG: 0"); admin = _admin; }

    function transferAdmin(address to) public onlyAdmin { require(to!=address(0), "SCREG: 0"); emit AdminTransferred(admin,to); admin = to; }

    function setStablecoin(
        address token,
        bool supported,
        bytes32 reserveId,
        address por,
        uint16 minReserveRatioBps,
        bytes32 defaultRailKey,
        bytes32 cctpRailKey,
        bytes32 ccipRailKey
    ) public onlyAdmin {
        Meta memory m = Meta({
            supported: supported,
            reserveId: reserveId,
            por: por,
            minReserveRatioBps: minReserveRatioBps,
            defaultRailKey: defaultRailKey,
            cctpRailKey: cctpRailKey,
            ccipRailKey: ccipRailKey
        });
        _meta[token] = m;
        emit StablecoinSet(token, m);
    }

    function get(address token) public view returns (Meta memory){ return _meta[token]; }
}
