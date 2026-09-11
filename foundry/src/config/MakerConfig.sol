// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { ILendingAdapter } from "src/interfaces/ILendingAdapter.sol";

/// @notice Which yield-protocol family an adapter belongs to. Descriptive
///         metadata for indexing/discovery: the adapter ADDRESS is what
///         contracts call; the kind is the readable protocol label.
enum AdapterKind {
    None,
    AaveV3,
    ERC4626,
    Stargate,
    PendlePT,
    SuperpositionUniHook
}

/// @notice One managed side of a maker's position: for `underlying`, the
///         maker's capital lives in `adapter` (of protocol family `kind`).
///         A managed side (autoManaged) is deployed JIT: tokens received are
///         deposited, tokens sent are withdrawn — by the router hooks.
struct SideConfig {
    address underlying;
    address adapter;
    AdapterKind kind;
    bool autoManaged;
}

event SideSet(
    address indexed maker,
    address indexed underlying,
    address indexed adapter,
    AdapterKind kind,
    bool autoManaged
);

/// @title MakerConfig
/// @notice Per-maker side registry: (maker, underlying) -> adapter. One
///         adapter per token: a maker that registers USDC -> Morpho deploys
///         every USDC revenue into Morpho, whatever the strategy — no token
///         discovery is ever needed (the fill hooks receive the token as a
///         parameter and resolve the adapter with one mapping lookup).
/// @dev Write is restricted to the maker itself (msg.sender); reads are
///      permissionless. The maker is trusted on config: a side registered
///      against capital the maker does not hold simply never quotes/fills
///      (the adapter's pull reverts atomically) — nothing can be lost.
contract MakerConfig {
    error InvalidSide(); // zero underlying/adapter or kind = None
    error AdapterInvalid(); // the address does not expose a non-empty name()

    mapping(address maker => mapping(address underlying => SideConfig)) private _sides;

    /// @notice Registers/overwrites the maker's managed sides. Each side maps
    ///         one underlying to one adapter (the protocol holding that side's
    ///         capital). Registered = managed: the router hooks will JIT-deploy
    ///         on receive and JIT-withdraw on send.
    function setSides(SideConfig[] calldata newSides) external {
        for (uint256 i = 0; i < newSides.length; i++) {
            SideConfig calldata s = newSides[i];
            if (s.underlying == address(0) || s.adapter == address(0) || s.kind == AdapterKind.None) {
                revert InvalidSide();
            }
            // sanity check: the address must be a real adapter — a low-level
            // staticcall must succeed AND return a non-empty name() (a codeless
            // address succeeds with empty returndata; a contract without the
            // selector fails the call; both are invalid).
            (, bytes memory ret) = s.adapter.staticcall(abi.encodeWithSelector(ILendingAdapter.name.selector));
            if (!_validName(ret)) revert AdapterInvalid();

            _sides[msg.sender][s.underlying] =
                SideConfig({ underlying: s.underlying, adapter: s.adapter, kind: s.kind, autoManaged: s.autoManaged });
            emit SideSet(msg.sender, s.underlying, s.adapter, s.kind, s.autoManaged);
        }
    }

    /// @notice The maker's side config for `underlying`. All-zero for an
    ///         unregistered (maker, token) pair — the hooks treat that as a
    ///         pass-through (no JIT deployment for that token).
    function sides(address maker, address underlying) external view returns (SideConfig memory) {
        return _sides[maker][underlying];
    }

    /// @dev True if `ret` is a well-formed ABI-encoded non-empty string
    ///      ([0..32) offset = 0x20, [32..64) length, [64..) data).
    function _validName(bytes memory ret) private pure returns (bool) {
        if (ret.length < 64) return false;
        uint256 offset;
        assembly {
            offset := mload(add(ret, 32))
        }
        if (offset != 0x20) return false;
        uint256 slen;
        assembly {
            slen := mload(add(ret, 64))
        }
        if (slen == 0) return false;
        if (ret.length < 64 + ((slen + 31) / 32) * 32) return false;
        return true;
    }
}
