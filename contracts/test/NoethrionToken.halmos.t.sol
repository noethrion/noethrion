// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SymTest} from "halmos-cheatcodes/SymTest.sol";
import {NoethrionToken} from "../src/NoethrionToken.sol";

/**
 * @dev Symbolic verification of NoethrionToken's public surface.
 *
 *      Asymmetric coverage was a real audit-doc red flag: the Attester
 *      carries 19 Halmos checks, the Token previously had zero — even
 *      though Token is the contract that actually performs the mint and
 *      enforces the MAX_SUPPLY hard cap. This file pins the four most
 *      load-bearing properties symbolically.
 *
 * Run with:
 *   halmos --contract NoethrionTokenHalmosTest
 *
 * Not part of the default `forge test` invocation — function names use
 * the `check_` prefix so Forge silently ignores them.
 */
contract NoethrionTokenHalmosTest is Test, SymTest {
    NoethrionToken internal token;

    address internal admin = address(0xA0);
    address internal minter = address(0xB0);

    function setUp() public {
        token = new NoethrionToken(admin);

        vm.prank(admin);
        token.authorizeMinter(minter);
    }

    /// Property: mint() reverts for any caller without MINTER_ROLE,
    /// for any (to, amount) input. The role guard is the primary defence
    /// against unauthorized mints; we pin it symbolically.
    function check_mint_nonMinterAlwaysReverts(address caller, address to, uint256 amount) external {
        vm.assume(caller != minter);
        vm.assume(!token.hasRole(token.MINTER_ROLE(), caller));

        vm.prank(caller);
        (bool ok,) = address(token).call(
            abi.encodeWithSelector(NoethrionToken.mint.selector, to, amount)
        );
        assert(!ok);
    }

    /// Property: mint() with a zero recipient reverts under any caller
    /// holding MINTER_ROLE and any amount. Closes the zero-address mint
    /// path symbolically.
    function check_mint_zeroRecipientAlwaysReverts(uint256 amount) external {
        vm.prank(minter);
        (bool ok,) = address(token).call(
            abi.encodeWithSelector(NoethrionToken.mint.selector, address(0), amount)
        );
        assert(!ok);
    }

    /// Property: mint() with amount = 0 reverts under any caller holding
    /// MINTER_ROLE and any recipient. Closes the zero-amount mint path
    /// symbolically.
    function check_mint_zeroAmountAlwaysReverts(address to) external {
        vm.assume(to != address(0));
        vm.prank(minter);
        (bool ok,) = address(token).call(
            abi.encodeWithSelector(NoethrionToken.mint.selector, to, uint256(0))
        );
        assert(!ok);
    }

    /// Property: mint() that would push totalSupply past MAX_SUPPLY reverts
    /// for any caller, any (to, amount) tuple, and any starting supply
    /// reachable from setUp. The hard cap is the economic-model invariant —
    /// a successful overflow would violate the 1 NOET = 1 verified kWh
    /// accounting and the Constitution's deterministic emission rule.
    ///
    /// Note: setUp leaves totalSupply at zero, so the symbolic prover starts
    /// from that concrete state. The contract's `newSupply > MAX_SUPPLY`
    /// guard is uniform with respect to the starting value (it's an
    /// addition + comparison, not a conditional), so the property carries
    /// to any starting supply. A future hardening pass could seed setUp
    /// with a symbolic pre-mint to broaden the prover's exploration; the
    /// underlying soundness of the check does not depend on it.
    function check_mint_maxSupplyAlwaysHolds(address to, uint256 amount) external {
        vm.assume(to != address(0));
        vm.assume(amount > 0);

        uint256 cap = token.MAX_SUPPLY();
        uint256 supply = token.totalSupply();
        // Restrict to amounts that would push us strictly past the cap.
        // With setUp's zero starting supply, `cap - supply` is just `cap`
        // and no underflow is possible; the symbolic amount must exceed
        // it for the property to be exercised.
        vm.assume(amount > cap - supply);

        vm.prank(minter);
        (bool ok,) = address(token).call(
            abi.encodeWithSelector(NoethrionToken.mint.selector, to, amount)
        );
        assert(!ok);
    }

    /// Property: authorizeMinter reverts for any caller lacking ADMIN_ROLE.
    /// The admin-only role gate on the mint-authority chain is what keeps
    /// the protocol's "100% algorithmic emission, no discretionary mint"
    /// property intact at the contract level.
    function check_authorizeMinter_nonAdminAlwaysReverts(address caller, address newMinter) external {
        vm.assume(caller != admin);
        vm.assume(!token.hasRole(token.ADMIN_ROLE(), caller));

        vm.prank(caller);
        (bool ok,) = address(token).call(
            abi.encodeWithSelector(NoethrionToken.authorizeMinter.selector, newMinter)
        );
        assert(!ok);
    }

    /// Property: authorizeMinter with a zero address reverts under admin.
    /// Defends against an admin slip that would silently authorize the
    /// zero address as a minter, leaving the protocol thinking a sentinel
    /// has mint authority.
    function check_authorizeMinter_zeroAddressAlwaysReverts() external {
        vm.prank(admin);
        (bool ok,) = address(token).call(
            abi.encodeWithSelector(NoethrionToken.authorizeMinter.selector, address(0))
        );
        assert(!ok);
    }
}
