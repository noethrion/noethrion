// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title NoethrionToken (NOET)
 * @notice ERC-20 token representing one verified kWh of green energy production
 *         attested by the Noethrion protocol. Minted only by an authorized
 *         attester contract; never minted by humans directly.
 *
 * @dev STATUS: v0.2 — production-leaning.
 *      - Decimals: 18 (1 NOET = 1 kWh, with 18-decimal subdivision)
 *      - Hard cap: 100,000,000,000 NOET (100B). Selected to comfortably
 *        envelope global cumulative renewable-energy production over the
 *        protocol's expected operating horizon (current global RE generation
 *        is ~10TWh/year cumulative; one NOET per kWh keeps the cap
 *        non-binding for centuries). Revisable only via a protocol spec
 *        revision before mainnet; v0.2 reference contract locks it.
 *      - Emission: 100% algorithmic, controlled by NoethrionAttester. The
 *        Foundation's contract has zero pre-mint and no separate mint path.
 *      - Foundation treasury: zero allocation in this contract (treasury
 *        allocation, if any, is handled by separate vesting contract).
 *
 * @custom:security-contact security@noethrion.com
 */
contract NoethrionToken is ERC20, ERC20Permit, AccessControl {
    // ─────────────────────────────────────────────────────────────────────────
    //  Roles
    // ─────────────────────────────────────────────────────────────────────────

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // ─────────────────────────────────────────────────────────────────────────
    //  Constants
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Hard cap on total supply: 100 billion NOET (one NOET = one
    ///         verified kWh). See contract-level NatSpec above for the
    ///         rationale and the revisable-before-mainnet constraint.
    uint256 public constant MAX_SUPPLY = 100_000_000_000 * 10 ** 18; // 100B NOET

    // ─────────────────────────────────────────────────────────────────────────
    //  Events
    // ─────────────────────────────────────────────────────────────────────────

    event MinterAuthorized(address indexed minter);
    event MinterRevoked(address indexed minter);

    // ─────────────────────────────────────────────────────────────────────────
    //  Errors
    // ─────────────────────────────────────────────────────────────────────────

    error MaxSupplyExceeded(uint256 attempted, uint256 cap);
    error ZeroAddress();
    error ZeroAmount();

    // ─────────────────────────────────────────────────────────────────────────
    //  Constructor
    // ─────────────────────────────────────────────────────────────────────────

    constructor(address admin) ERC20("Noethrion", "NOET") ERC20Permit("Noethrion") {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Minting
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Mint NOET to a beneficiary. Callable only by NoethrionAttester.
     * @param to Recipient address (energy producer or their delegate).
     * @param amount Amount in wei-scale NOET (18 decimals).
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        uint256 newSupply = totalSupply() + amount;
        if (newSupply > MAX_SUPPLY) revert MaxSupplyExceeded(newSupply, MAX_SUPPLY);

        _mint(to, amount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Admin
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Authorize a new minter (typically the NoethrionAttester contract).
     */
    function authorizeMinter(address minter) external onlyRole(ADMIN_ROLE) {
        if (minter == address(0)) revert ZeroAddress();
        _grantRole(MINTER_ROLE, minter);
        emit MinterAuthorized(minter);
    }

    function revokeMinter(address minter) external onlyRole(ADMIN_ROLE) {
        _revokeRole(MINTER_ROLE, minter);
        emit MinterRevoked(minter);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  View helpers
    // ─────────────────────────────────────────────────────────────────────────

    function remainingMintable() external view returns (uint256) {
        uint256 supply = totalSupply();
        return supply >= MAX_SUPPLY ? 0 : MAX_SUPPLY - supply;
    }
}
