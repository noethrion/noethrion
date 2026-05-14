// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SymTest} from "halmos-cheatcodes/SymTest.sol";
import {NoethrionAttester} from "../src/NoethrionAttester.sol";
import {NoethrionToken} from "../src/NoethrionToken.sol";

/**
 * @dev Symbolic execution checks via Halmos.
 *
 * Halmos proves properties over the *whole input space* (subject to the loop
 * unrolling bound `--loop`), not just the random samples a fuzzer would visit.
 * The properties here are not redundant with the fuzz suite — fuzz catches
 * empirical violations, Halmos proves their absence (within the unroll bound).
 *
 * Run with:
 *   halmos --contract NoethrionAttesterHalmosTest
 *
 * NOTE: not part of the default `forge test` run — Halmos is run as a
 * supplementary verifier. See docs/audit/smart-contracts-audit.md.
 */
contract NoethrionAttesterHalmosTest is Test, SymTest {
    NoethrionAttester internal attester;
    NoethrionToken internal token;

    address internal admin = address(0xA0);
    address internal validator = address(0x4001);
    address internal validator2 = address(0x4002);

    function setUp() public {
        attester = new NoethrionAttester(admin, 1 hours, 1);
        token = new NoethrionToken(admin);

        bytes32 vRole = attester.VALIDATOR_ROLE();
        vm.startPrank(admin);
        attester.grantRole(vRole, validator);
        attester.grantRole(vRole, validator2);
        attester.setTokenContract(address(token));
        token.authorizeMinter(address(attester));
        vm.stopPrank();
    }

    /// Halmos input symbols: epoch, root, totalKwh are universally quantified.
    /// Property: a successful proposeBatch always records exactly one vote from
    /// the proposer, regardless of any input. A regression that decoupled the
    /// vote count from the proposer's identity would be caught here.
    function check_proposeBatch_alwaysSetsFirstVote(uint64 epoch, bytes32 root, uint128 totalKwh) external {
        vm.assume(epoch != 0); // 0 timestamp would collide with the "not proposed" sentinel after warp; exclude

        vm.prank(validator);
        attester.proposeBatch(epoch, root, totalKwh);

        assert(attester.voteCount(epoch) == 1);
        assert(attester.voted(epoch, validator));
    }

    /// Property: setThreshold(0) reverts unconditionally for any admin call.
    /// Catches a regression that introduced a code path bypassing the zero check.
    function check_setThreshold_zeroAlwaysReverts() external {
        vm.prank(admin);
        (bool ok,) = address(attester).call(abi.encodeWithSelector(NoethrionAttester.setThreshold.selector, uint256(0)));
        assert(!ok);
    }

    /// Property: the constructor's zero-admin guard holds for the entire admin space.
    /// (Reproves the unit test under symbolic input — useful as a sanity check
    /// that no compiler-level optimisation has rewritten the require.)
    function check_constructor_zeroAdminReverts(uint256 cw, uint256 thr) external {
        vm.assume(thr != 0); // isolate the admin-zero condition from the threshold-zero one
        (bool ok,) = address(this).call(
            abi.encodeWithSignature(
                "deployWithAdmin(address,uint256,uint256)", address(0), cw, thr
            )
        );
        assert(!ok);
    }

    /// External helper used by `check_constructor_zeroAdminReverts` — exists only
    /// so the constructor call can be wrapped in a try/catch context.
    function deployWithAdmin(address a, uint256 cw, uint256 thr) external returns (NoethrionAttester) {
        return new NoethrionAttester(a, cw, thr);
    }

    /// Property: a second voteBatch call by the same validator on the same epoch
    /// always reverts, regardless of timing or other state. This is the
    /// double-vote invariant in formal form.
    function check_voteBatch_doubleVoteAlwaysReverts(uint64 epoch, bytes32 root, uint128 totalKwh) external {
        vm.assume(epoch != 0);

        vm.prank(validator);
        attester.proposeBatch(epoch, root, totalKwh);

        // First voteBatch as a fresh validator — should succeed.
        vm.prank(validator2);
        attester.voteBatch(epoch);

        // Second voteBatch by the same validator — must revert under all states.
        vm.prank(validator2);
        (bool ok,) =
            address(attester).call(abi.encodeWithSelector(NoethrionAttester.voteBatch.selector, epoch));
        assert(!ok);
    }

    /// Property: voteCount monotonically increases under voteBatch (no underflow
    /// or off-by-one path can shrink it).
    function check_voteBatch_voteCountMonotonic(uint64 epoch, bytes32 root, uint128 totalKwh) external {
        vm.assume(epoch != 0);

        vm.prank(validator);
        attester.proposeBatch(epoch, root, totalKwh);

        uint256 before = attester.voteCount(epoch);

        vm.prank(validator2);
        attester.voteBatch(epoch);

        uint256 afterVote = attester.voteCount(epoch);
        assert(afterVote >= before);
        assert(afterVote == before + 1);
    }

    /// Property: finalizeBatch reverts for any block.timestamp strictly less than
    /// the challenge-window unlock. Catches a regression that miscompared the
    /// threshold (e.g., `<=` instead of `<`) or swapped operands.
    function check_finalizeBatch_revertsBeforeWindow(uint64 epoch, bytes32 root, uint128 totalKwh, uint256 warpDelta) external {
        vm.assume(epoch != 0);
        vm.assume(warpDelta < 1 hours); // strictly inside the challenge window

        vm.prank(validator);
        attester.proposeBatch(epoch, root, totalKwh);

        // Move forward but strictly less than the full window.
        vm.warp(block.timestamp + warpDelta);

        (bool ok,) =
            address(attester).call(abi.encodeWithSelector(NoethrionAttester.finalizeBatch.selector, epoch));
        assert(!ok);
    }

    /// Property: claim() with a zero beneficiary reverts under any (epoch, amount)
    /// regardless of proof contents. Defends against an empty-proof + zero-target
    /// path being treated as a valid claim.
    function check_claim_zeroBeneficiaryAlwaysReverts(uint64 epoch, uint128 amount) external {
        bytes32[] memory emptyProof = new bytes32[](0);
        (bool ok,) = address(attester).call(
            abi.encodeWithSelector(NoethrionAttester.claim.selector, epoch, emptyProof, address(0), amount)
        );
        assert(!ok);
    }

    /// Property: claim() with amount == 0 reverts under any non-zero beneficiary
    /// and any epoch. Pairs with ZeroBeneficiary above to bound the input rejection
    /// surface tightly.
    function check_claim_zeroAmountAlwaysReverts(uint64 epoch, address b) external {
        vm.assume(b != address(0));
        bytes32[] memory emptyProof = new bytes32[](0);
        (bool ok,) = address(attester).call(
            abi.encodeWithSelector(NoethrionAttester.claim.selector, epoch, emptyProof, b, uint128(0))
        );
        assert(!ok);
    }

    /// Property: when the contract is paused, proposeBatch reverts for any
    /// (epoch, root, totalKwh) — the pause kill switch covers the propose path
    /// under all inputs, not just the ones the unit test sampled.
    function check_pause_blocksProposeBatch_alwaysReverts(uint64 epoch, bytes32 root, uint128 totalKwh) external {
        vm.prank(admin);
        attester.pause();

        vm.prank(validator);
        (bool ok,) = address(attester).call(
            abi.encodeWithSelector(NoethrionAttester.proposeBatch.selector, epoch, root, totalKwh)
        );
        assert(!ok);
    }

    /// Property: when the contract is paused, voteBatch reverts for any epoch
    /// and any caller. Pause kill switch covers the vote path symmetrically.
    function check_pause_blocksVoteBatch_alwaysReverts(uint64 epoch) external {
        vm.prank(admin);
        attester.pause();

        vm.prank(validator);
        (bool ok,) = address(attester).call(
            abi.encodeWithSelector(NoethrionAttester.voteBatch.selector, epoch)
        );
        assert(!ok);
    }

    /// Property: when the contract is paused, finalizeBatch reverts for any
    /// epoch. Pause kill switch covers the finalize path symmetrically.
    function check_pause_blocksFinalizeBatch_alwaysReverts(uint64 epoch) external {
        vm.prank(admin);
        attester.pause();

        (bool ok,) = address(attester).call(
            abi.encodeWithSelector(NoethrionAttester.finalizeBatch.selector, epoch)
        );
        assert(!ok);
    }

    /// Property: when the contract is paused, claim reverts for any
    /// (epoch, beneficiary, amount). Pause kill switch covers the claim
    /// path symmetrically; completes the 4-way coverage matrix for the
    /// pause-blocks-mutations invariant.
    function check_pause_blocksClaim_alwaysReverts(
        uint64 epoch,
        address beneficiary,
        uint128 amount
    ) external {
        vm.prank(admin);
        attester.pause();

        bytes32[] memory emptyProof = new bytes32[](0);
        (bool ok,) = address(attester).call(
            abi.encodeWithSelector(
                NoethrionAttester.claim.selector, epoch, emptyProof, beneficiary, amount
            )
        );
        assert(!ok);
    }

    /// Property: end-to-end single-leaf claim mints exactly `amount` tokens
    /// to `beneficiary` for any non-zero (beneficiary, amount, epoch) tuple.
    /// In a single-leaf Merkle tree, `root == leaf` and the inclusion proof
    /// is empty. The bound here is symbolic over the entire input space the
    /// claim path actually sees.
    function check_claim_singleLeafMintsExactAmount(uint64 epoch, address beneficiary, uint128 amount) external {
        vm.assume(beneficiary != address(0));
        vm.assume(amount != 0);
        vm.assume(epoch != 0);

        bytes32 leaf = keccak256(abi.encode(block.chainid, address(attester), beneficiary, amount, epoch));

        vm.prank(validator);
        attester.proposeBatch(epoch, leaf, amount);

        vm.warp(block.timestamp + 1 hours + 1);
        attester.finalizeBatch(epoch);

        uint256 balBefore = token.balanceOf(beneficiary);
        bytes32[] memory emptyProof = new bytes32[](0);
        attester.claim(epoch, emptyProof, beneficiary, amount);
        uint256 balAfter = token.balanceOf(beneficiary);

        assert(balAfter == balBefore + amount);
        assert(attester.claimed(leaf));
    }

    /// Property: a second claim against the same leaf reverts unconditionally
    /// (per-leaf double-spend protection). Independent of any other state.
    function check_claim_doubleClaimAlwaysReverts(uint64 epoch, address beneficiary, uint128 amount) external {
        vm.assume(beneficiary != address(0));
        vm.assume(amount != 0);
        vm.assume(epoch != 0);

        bytes32 leaf = keccak256(abi.encode(block.chainid, address(attester), beneficiary, amount, epoch));

        vm.prank(validator);
        attester.proposeBatch(epoch, leaf, amount);
        vm.warp(block.timestamp + 1 hours + 1);
        attester.finalizeBatch(epoch);

        bytes32[] memory emptyProof = new bytes32[](0);
        attester.claim(epoch, emptyProof, beneficiary, amount);

        (bool ok,) = address(attester).call(
            abi.encodeWithSelector(
                NoethrionAttester.claim.selector, epoch, emptyProof, beneficiary, amount
            )
        );
        assert(!ok);
    }

    /// Property: slash() stores the evidence hash and leaves the target
    /// without VALIDATOR_ROLE for any non-zero target when called by admin.
    /// Whether the target had the role before is irrelevant — _revokeRole
    /// is a no-op on an address that did not hold it; the evidence record
    /// fires either way (documented as intentional in the contract's NatSpec
    /// and verified by `test_Slash_OnNonValidatorAddress_StillRecordsEvidence`).
    function check_slash_storesEvidenceAndClearsRole(address victim, bytes32 evidenceHash) external {
        vm.assume(victim != address(0));

        vm.prank(admin);
        attester.slash(victim, evidenceHash);

        assert(!attester.hasRole(attester.VALIDATOR_ROLE(), victim));
        assert(attester.slashEvidence(victim) == evidenceHash);
    }

    /// Property: slash() reverts when target is the zero address. The
    /// ZeroAddress guard is the smallest defensive check on slash; pin it
    /// symbolically so an optimisation cannot elide the branch.
    function check_slash_zeroAddressAlwaysReverts(bytes32 evidenceHash) external {
        vm.prank(admin);
        (bool ok,) = address(attester).call(
            abi.encodeWithSelector(NoethrionAttester.slash.selector, address(0), evidenceHash)
        );
        assert(!ok);
    }

    /// Property: setChallengeWindow updates the storage value for valid input
    /// (non-zero and within uint64 range). The non-zero floor closes the
    /// zero-bypass attack (reviewer C-2) and the uint64 cap keeps the per-batch
    /// snapshot lossless. Together with the constructor InvalidChallengeWindow
    /// revert this pins the only two write sites for `challengeWindow`.
    function check_setChallengeWindow_updatesValue(uint256 newWindow) external {
        vm.assume(newWindow > 0 && newWindow <= type(uint64).max);
        vm.prank(admin);
        attester.setChallengeWindow(newWindow);
        assert(attester.challengeWindow() == newWindow);
    }

    /// Property: setChallengeWindow CANNOT retroactively change the unlock
    /// delay of an already-proposed batch. The per-batch
    /// `challengeWindowAtPropose` snapshot is the binding value; the live
    /// storage is only read by future proposals. Symmetric guarantee to
    /// `thresholdAtPropose` (reviewer H-3 fix; this is reviewer C-2 fix).
    function check_setChallengeWindow_doesNotAffectInFlightBatch(
        uint64 epoch,
        bytes32 root,
        uint128 totalKwh,
        uint256 newWindow
    ) external {
        vm.assume(epoch != 0);
        vm.assume(newWindow > 0 && newWindow <= type(uint64).max);

        vm.prank(validator);
        attester.proposeBatch(epoch, root, totalKwh);
        (,,,,,,, uint64 windowAtPropose) = attester.batches(epoch);

        vm.prank(admin);
        attester.setChallengeWindow(newWindow);

        (,,,,,,, uint64 windowAfter) = attester.batches(epoch);
        assert(windowAfter == windowAtPropose);
    }

    /// Property: setChallengeWindow reverts for any non-admin caller.
    /// Catches a regression that removed the onlyRole(ADMIN_ROLE) modifier
    /// or changed the role hash.
    function check_setChallengeWindow_nonAdminReverts(address caller, uint256 newWindow) external {
        vm.assume(caller != admin);
        vm.assume(!attester.hasRole(attester.ADMIN_ROLE(), caller));

        vm.prank(caller);
        (bool ok,) = address(attester).call(
            abi.encodeWithSelector(NoethrionAttester.setChallengeWindow.selector, newWindow)
        );
        assert(!ok);
    }
}
