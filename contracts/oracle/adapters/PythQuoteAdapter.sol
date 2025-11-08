// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IQuoteAdapter} from "../../interfaces/IQuoteAdapter.sol";

struct PythPrice {
    int64 price;     // price * 10^expo
    int32 expo;      // typically negative (e.g., -8)
    uint64 publishTime;
}

interface IPyth {
    function getPriceNoOlderThan(bytes32 id, uint age) external view returns (PythPrice memory);
}

/// @title PythQuoteAdapter
/// @notice Returns USD quotes for registered instruments via Pyth price ids.
///         Normalizes to 18 decimals. Freshness via getPriceNoOlderThan.
contract PythQuoteAdapter is IQuoteAdapter, AccessControl {
    bytes32 public constant ADMIN = keccak256("ADMIN");

    IPyth public pyth;

    struct PythMap {
        bytes32 priceId;
        uint64 maxAgeSec;
    }

    // instrument => pyth id
    mapping(address => PythMap) public ids;

    event PythSet(address indexed instrument, bytes32 priceId, uint64 maxAgeSec);
    event PythAddressSet(address pyth);

    constructor(address governor, address pythAddress) {
        _grantRole(DEFAULT_ADMIN_ROLE, governor);
        _grantRole(ADMIN, governor);
        pyth = IPyth(pythAddress);
        emit PythAddressSet(pythAddress);
    }

    function setPyth(address pythAddress) public onlyRole(ADMIN) {
        pyth = IPyth(pythAddress);
        emit PythAddressSet(pythAddress);
    }

    function setPriceId(address instrument, bytes32 priceId, uint64 maxAgeSec) public onlyRole(ADMIN) {
        require(instrument != address(0) && priceId != bytes32(0), "bad");
        ids[instrument] = PythMap(priceId, maxAgeSec);
        emit PythSet(instrument, priceId, maxAgeSec);
    }

    /// @inheritdoc IQuoteAdapter
    function quoteInCash(address instrument) public view returns (uint256 price, uint8 decimals, uint64 lastUpdate) {
        PythMap memory m = ids[instrument];
        require(m.priceId != bytes32(0), "no_pyth");
        PythPrice memory p = pyth.getPriceNoOlderThan(m.priceId, m.maxAgeSec == 0 ? type(uint).max : m.maxAgeSec);
        require(p.price > 0, "bad_pyth");

        // convert price * 10^expo to 18 decimals
        int32 expo = p.expo;
        uint256 abs = uint256(int256(p.price));
        if (expo >= 0) {
            // scale up then to 18
            uint256 withExpo = abs * (10 ** uint32(uint32(expo)));
            if (18 >= 0) {
                price = withExpo * (10 ** 18);
                decimals = 18;
            }
        } else {
            // expo negative: divide
            uint32 neg = uint32(uint32(-expo));
            if (neg <= 18) {
                price = abs * (10 ** (18 - neg));
                decimals = 18;
            } else {
                // downscale beyond 18
                price = abs / (10 ** (neg - 18));
                decimals = 18;
            }
        }
        lastUpdate = p.publishTime;
    }

    /// @inheritdoc IQuoteAdapter
    function isFresh(address instrument, uint64 maxAgeSec) public view returns (bool) {
        PythMap memory m = ids[instrument];
        require(m.priceId != bytes32(0), "no_pyth");
        uint64 age = (m.maxAgeSec == 0 ? maxAgeSec : (maxAgeSec == 0 ? m.maxAgeSec : maxAgeSec));
        // Using the call below throws if too old; catch by static analysis:
        PythPrice memory p = pyth.getPriceNoOlderThan(m.priceId, age == 0 ? type(uint).max : age);
        return p.publishTime + age >= block.timestamp;
    }
}
