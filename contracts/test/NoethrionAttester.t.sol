// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {NoethrionAttester} from "../src/NoethrionAttester.sol";
import {NoethrionToken} from "../src/NoethrionToken.sol";

contract NoethrionAttesterTest is Test {
    NoethrionAttester internal attester;
    NoethrionToken internal token;

    address internal admin = makeAddr("admin");
    address internal validator = makeAddr("validator");
    address internal validator2 = makeAddr("validator2");
    address internal validator3 = makeAddr("validator3");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant CHALLENGE_WINDOW = 1 hours;
    uint256 internal constant DEFAULT_THRESHOLD = 1;

    function setUp() public {
        attester = new NoethrionAttester(admin, CHALLENGE_WINDOW, DEFAULT_THRESHOLD);
        token = new NoethrionToken(admin);

        bytes32 validatorRole = attester.VALIDATOR_ROLE();
        vm.startPrank(admin);
        attester.grantRole(validatorRole, validator);
        attester.grantRole(validatorRole, validator2);
        attester.grantRole(validatorRole, validator3);
        attester.setTokenContract(address(token));
        token.authorizeMinter(address(attester));
        vm.stopPrank();
    }

    // Helper — hash a sorted pair the way OpenZeppelin MerkleProof expects.
    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    // ───── Construction ─────

    function test_InitialState() public view {
        assertEq(attester.challengeWindow(), CHALLENGE_WINDOW);
        assertEq(attester.threshold(), DEFAULT_THRESHOLD);
        assertEq(attester.latestEpoch(), 0);
        assertTrue(attester.hasRole(attester.ADMIN_ROLE(), admin));
    }

    function test_Constructor_RevertsOnZeroAdmin() public {
        vm.expectRevert(NoethrionAttester.ZeroAddress.selector);
        new NoethrionAttester(address(0), CHALLENGE_WINDOW, DEFAULT_THRESHOLD);
    }

    function test_Constructor_RevertsOnZeroThreshold() public {
        vm.expectRevert(
            abi.encodeWithSelector(NoethrionAttester.InvalidThreshold.selector, uint256(0))
        );
        new NoethrionAttester(admin, CHALLENGE_WINDOW, 0);
    }

    function test_Constructor_AcceptsThresholdOne() public {
        NoethrionAttester a = new NoethrionAttester(admin, CHALLENGE_WINDOW, 1);
        assertEq(a.threshold(), 1);
    }

    function test_Constructor_RevertsOnZeroChallengeWindow() public {
        vm.expectRevert(NoethrionAttester.InvalidChallengeWindow.selector);
        new NoethrionAttester(admin, 0, DEFAULT_THRESHOLD);
    }

    function test_Constructor_RevertsOnThresholdAboveUint64Max() public {
        uint256 tooBig = uint256(type(uint64).max) + 1;
        vm.expectRevert(
            abi.encodeWithSelector(NoethrionAttester.InvalidThreshold.selector, tooBig)
        );
        new NoethrionAttester(admin, CHALLENGE_WINDOW, tooBig);
    }

    // ───── Propose ─────

    function test_ProposeBatch_Succeeds() public {
        bytes32 root = keccak256("batch-1");
        vm.prank(validator);
        attester.proposeBatch(1, root, 1_000_000);

        (bytes32 r, uint64 epoch, uint128 kwh,, address proposer, bool finalized,,) =
            attester.batches(1);

        assertEq(r, root);
        assertEq(epoch, 1);
        assertEq(kwh, 1_000_000);
        assertEq(proposer, validator);
        assertFalse(finalized);
    }

    function test_ProposeBatch_CountsAsFirstVote() public {
        vm.prank(validator);
        attester.proposeBatch(1, keccak256("x"), 1);

        assertEq(attester.voteCount(1), 1);
        assertTrue(attester.voted(1, validator));
    }

    function test_ProposeBatch_RevertsForNonValidator() public {
        vm.prank(alice);
        vm.expectRevert();
        attester.proposeBatch(1, keccak256("x"), 100);
    }

    function test_ProposeBatch_RevertsOnDuplicateEpoch() public {
        vm.startPrank(validator);
        attester.proposeBatch(1, keccak256("a"), 100);
        vm.expectRevert(
            abi.encodeWithSelector(NoethrionAttester.EpochAlreadyProposed.selector, uint64(1))
        );
        attester.proposeBatch(1, keccak256("b"), 200);
        vm.stopPrank();
    }

    // ───── Vote ─────

    function test_VoteBatch_IncrementsCount() public {
        vm.prank(validator);
        attester.proposeBatch(1, keccak256("a"), 100);

        vm.prank(validator2);
        attester.voteBatch(1);

        assertEq(attester.voteCount(1), 2);
        assertTrue(attester.voted(1, validator));
        assertTrue(attester.voted(1, validator2));
    }

    function test_VoteBatch_RevertsOnDoubleVote() public {
        vm.prank(validator);
        attester.proposeBatch(1, keccak256("a"), 100);

        // The proposer's vote is already counted — voting again is a double-vote.
        vm.prank(validator);
        vm.expectRevert(
            abi.encodeWithSelector(NoethrionAttester.AlreadyVoted.selector, uint64(1), validator)
        );
        attester.voteBatch(1);
    }

    function test_VoteBatch_RevertsOnDoubleVote_OtherValidator() public {
        vm.prank(validator);
        attester.proposeBatch(1, keccak256("a"), 100);

        vm.startPrank(validator2);
        attester.voteBatch(1);
        vm.expectRevert(
            abi.encodeWithSelector(NoethrionAttester.AlreadyVoted.selector, uint64(1), validator2)
        );
        attester.voteBatch(1);
        vm.stopPrank();
    }

    function test_VoteBatch_RevertsForNonValidator() public {
        vm.prank(validator);
        attester.proposeBatch(1, keccak256("a"), 100);

        vm.prank(alice);
        vm.expectRevert();
        attester.voteBatch(1);
    }

    function test_VoteBatch_RevertsOnUnknownProposal() public {
        vm.prank(validator);
        vm.expectRevert(
            abi.encodeWithSelector(NoethrionAttester.EpochNotFound.selector, uint64(99))
        );
        attester.voteBatch(99);
    }

    function test_VoteBatch_RevertsOnFinalized() public {
        // threshold = 1 by default, so propose + warp + finalize works in one go.
        vm.prank(validator);
        attester.proposeBatch(1, keccak256("a"), 100);

        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        attester.finalizeBatch(1);

        // After finalization, late votes are meaningless and would spam BatchVoted.
        vm.prank(validator2);
        vm.expectRevert(
            abi.encodeWithSelector(NoethrionAttester.BatchAlreadyFinalized.selector, uint64(1))
        );
        attester.voteBatch(1);
    }

    function test_SlashedValidator_PriorVoteStillCounts() public {
        // threshold = 2 — proposer + one extra vote needed.
        vm.prank(admin);
        attester.setThreshold(2);

        vm.prank(validator);
        attester.proposeBatch(1, keccak256("a"), 100);

        vm.prank(validator2);
        attester.voteBatch(1);  // quorum now satisfied (validator + validator2 = 2)

        assertEq(attester.voteCount(1), 2);

        // Now slash validator2 — their prior vote MUST still count per ADR-006 open Q3.
        vm.prank(admin);
        attester.slash(validator2, keccak256("evidence-after-vote"));

        // voteCount unchanged
        assertEq(attester.voteCount(1), 2);

        // finalize still succeeds after challenge window
        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        attester.finalizeBatch(1);
        (,,,,, bool finalized,,) = attester.batches(1);
        assertTrue(finalized);
    }

    function test_Slash_OnNonValidatorAddress_StillRecordsEvidence() public {
        // Documents the intentional behaviour: slash() does NOT precondition on
        // hasRole. An admin can record evidence against any non-zero address;
        // _revokeRole on an address that never held the role is a no-op in
        // OpenZeppelin AccessControl, but the evidence + event still fire.
        // Operational note: off-chain alerting on ValidatorSlashed should
        // cross-check hasRole(VALIDATOR_ROLE, validator) before paging.
        bytes32 evidence = keccak256("evidence-on-non-validator");
        assertFalse(attester.hasRole(attester.VALIDATOR_ROLE(), alice));

        vm.prank(admin);
        attester.slash(alice, evidence);

        assertEq(attester.slashEvidence(alice), evidence);
        assertFalse(attester.hasRole(attester.VALIDATOR_ROLE(), alice));
    }

    // ───── Finalize ─────

    function test_FinalizeBatch_RevertsBeforeWindow() public {
        vm.prank(validator);
        attester.proposeBatch(1, keccak256("a"), 100);

        vm.expectRevert();
        attester.finalizeBatch(1);
    }

    function test_FinalizeBatch_SucceedsAfterWindow() public {
        vm.prank(validator);
        attester.proposeBatch(1, keccak256("a"), 100);

        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        attester.finalizeBatch(1);

        (,,,,, bool finalized,,) = attester.batches(1);
        assertTrue(finalized);
        assertEq(attester.latestEpoch(), 1);
    }

    function test_FinalizeBatch_RevertsOnUnknownEpoch() public {
        vm.expectRevert(
            abi.encodeWithSelector(NoethrionAttester.EpochNotFound.selector, uint64(99))
        );
        attester.finalizeBatch(99);
    }

    function test_FinalizeBatch_RevertsOnDoubleFinalize() public {
        vm.prank(validator);
        attester.proposeBatch(1, keccak256("a"), 100);

        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        attester.finalizeBatch(1);

        vm.expectRevert(
            abi.encodeWithSelector(NoethrionAttester.BatchAlreadyFinalized.selector, uint64(1))
        );
        attester.finalizeBatch(1);
    }

    function test_FinalizeBatch_RevertsBelowThreshold() public {
        // Raise threshold to 3 — proposer is 1 vote, validator2 voting brings to 2 — still below.
        vm.prank(admin);
        attester.setThreshold(3);

        vm.prank(validator);
        attester.proposeBatch(1, keccak256("a"), 100);

        vm.prank(validator2);
        attester.voteBatch(1);

        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                NoethrionAttester.InsufficientVotes.selector, uint64(1), uint256(2), uint256(3)
            )
        );
        attester.finalizeBatch(1);
    }

    function test_FinalizeBatch_SucceedsAtThreshold() public {
        vm.prank(admin);
        attester.setThreshold(3);

        vm.prank(validator);
        attester.proposeBatch(1, keccak256("a"), 100);
        vm.prank(validator2);
        attester.voteBatch(1);
        vm.prank(validator3);
        attester.voteBatch(1);

        assertEq(attester.voteCount(1), 3);

        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        attester.finalizeBatch(1);

        (,,,,, bool finalized,,) = attester.batches(1);
        assertTrue(finalized);
    }

    // ───── Pause ─────

    function test_Pause_BlocksSubmission() public {
        vm.prank(admin);
        attester.pause();

        vm.prank(validator);
        vm.expectRevert();
        attester.proposeBatch(1, keccak256("a"), 100);
    }

    function test_Pause_BlocksVote() public {
        vm.prank(validator);
        attester.proposeBatch(1, keccak256("a"), 100);

        vm.prank(admin);
        attester.pause();

        vm.prank(validator2);
        vm.expectRevert();
        attester.voteBatch(1);
    }

    function test_Pause_BlocksFinalize() public {
        vm.prank(validator);
        attester.proposeBatch(1, keccak256("a"), 100);
        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);

        vm.prank(admin);
        attester.pause();

        vm.expectRevert();
        attester.finalizeBatch(1);
    }

    function test_Pause_BlocksClaim() public {
        (,, , bytes32[] memory proof) = _setupTwoLeafBatch();
        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        attester.finalizeBatch(1);

        vm.prank(admin);
        attester.pause();

        vm.expectRevert();
        attester.claim(uint64(1), proof, alice, uint128(100 ether));
    }

    function test_Pause_OnlyPauserRole() public {
        vm.prank(alice);
        vm.expectRevert();
        attester.pause();
    }

    function test_Unpause_RestoresSubmission() public {
        vm.startPrank(admin);
        attester.pause();
        attester.unpause();
        vm.stopPrank();

        // After unpause, the validator API works again.
        vm.prank(validator);
        attester.proposeBatch(1, keccak256("a"), 100);
        assertEq(attester.voteCount(1), 1);
    }

    function test_Unpause_OnlyPauserRole() public {
        vm.prank(admin);
        attester.pause();

        vm.prank(alice);
        vm.expectRevert();
        attester.unpause();
    }

    // ───── setChallengeWindow ─────

    function test_SetChallengeWindow_OnlyAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        attester.setChallengeWindow(2 hours);
    }

    function test_SetChallengeWindow_UpdatesValue() public {
        vm.prank(admin);
        attester.setChallengeWindow(2 hours);
        assertEq(attester.challengeWindow(), 2 hours);
    }

    // ───── setTokenContract ─────

    function test_SetTokenContract_OnlyAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        attester.setTokenContract(address(0xdead));
    }

    function test_SetTokenContract_RevertsOnZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(NoethrionAttester.ZeroAddress.selector);
        attester.setTokenContract(address(0));
    }

    function test_SetTokenContract_UpdatesValue() public {
        NoethrionToken freshToken = new NoethrionToken(admin);
        vm.prank(admin);
        attester.setTokenContract(address(freshToken));
        assertEq(attester.tokenContract(), address(freshToken));
    }

    // ───── setThreshold ─────

    function test_SetThreshold_OnlyAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        attester.setThreshold(5);
    }

    function test_SetThreshold_RevertsOnZero() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(NoethrionAttester.InvalidThreshold.selector, uint256(0))
        );
        attester.setThreshold(0);
    }

    function test_SetThreshold_UpdatesValue() public {
        vm.prank(admin);
        attester.setThreshold(7);
        assertEq(attester.threshold(), 7);
    }

    function test_SetThreshold_RevertsAboveUint64Max() public {
        uint256 tooBig = uint256(type(uint64).max) + 1;
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(NoethrionAttester.InvalidThreshold.selector, tooBig)
        );
        attester.setThreshold(tooBig);
    }

    // ───── Threshold snapshot at propose time ─────

    function test_FinalizeBatch_UsesProposeTimeThreshold_LowerLater() public {
        // Propose with threshold = 3, then admin lowers to 2 BEFORE quorum is
        // reached. The batch must still require 3 votes — setThreshold MUST
        // NOT retroactively unlock an in-flight batch.
        vm.prank(admin);
        attester.setThreshold(3);

        vm.prank(validator);
        attester.proposeBatch(1, keccak256("a"), 100);

        vm.prank(validator2);
        attester.voteBatch(1);
        // voteCount = 2; setThreshold to 2 would otherwise pass quorum.

        vm.prank(admin);
        attester.setThreshold(2);

        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                NoethrionAttester.InsufficientVotes.selector, uint64(1), uint256(2), uint256(3)
            )
        );
        attester.finalizeBatch(1);

        // After one more vote (back to the original required 3) it does finalize.
        vm.prank(validator3);
        attester.voteBatch(1);
        attester.finalizeBatch(1);
        (,,,,, bool finalized,,) = attester.batches(1);
        assertTrue(finalized);
    }

    function test_FinalizeBatch_UsesProposeTimeThreshold_HigherLater() public {
        // Propose with threshold = 2, then admin raises to 5 BEFORE finalize.
        // The batch must still finalize on its original 2-vote requirement —
        // setThreshold MUST NOT retroactively block an in-flight batch.
        vm.prank(admin);
        attester.setThreshold(2);

        vm.prank(validator);
        attester.proposeBatch(1, keccak256("a"), 100);
        vm.prank(validator2);
        attester.voteBatch(1);

        vm.prank(admin);
        attester.setThreshold(5);

        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        attester.finalizeBatch(1);

        (,,,,, bool finalized,,) = attester.batches(1);
        assertTrue(finalized);
    }

    function test_ProposeBatch_StoresThresholdAtPropose() public {
        vm.prank(admin);
        attester.setThreshold(4);
        vm.prank(validator);
        attester.proposeBatch(1, keccak256("a"), 100);
        (,,,,,, uint64 tap,) = attester.batches(1);
        assertEq(tap, 4);
    }

    function test_ProposeBatch_EmitsThresholdAtProposeInEvent() public {
        vm.prank(admin);
        attester.setThreshold(3);
        bytes32 root = keccak256("evt-check");
        vm.expectEmit(true, true, true, true, address(attester));
        emit NoethrionAttester.BatchProposed(uint64(7), root, uint128(500), validator, uint64(3));
        vm.prank(validator);
        attester.proposeBatch(7, root, 500);
    }

    // ───── Challenge-window snapshot at propose time ─────

    function test_ProposeBatch_StoresChallengeWindowAtPropose() public {
        vm.prank(validator);
        attester.proposeBatch(1, keccak256("a"), 100);
        (,,,,,,, uint64 cwap) = attester.batches(1);
        assertEq(cwap, uint64(CHALLENGE_WINDOW));
    }

    function test_FinalizeBatch_UsesProposeTimeChallengeWindow_LowerLater() public {
        // Propose with default 1h window, then admin lowers (well, in this
        // test we'd love to test setting to 0 but setChallengeWindow now
        // rejects 0; instead lower to 1 second to prove the snapshot still
        // binds the original 1h unlock).
        vm.prank(validator);
        attester.proposeBatch(1, keccak256("a"), 100);

        vm.prank(admin);
        attester.setChallengeWindow(1);

        // Right after propose + a single new second: NEITHER the original
        // 1h window NOR the shrunk 1-second window has elapsed for an unwarp'd
        // clock — but the contract should still require the snapshot's full
        // hour, not the live value. We assert finalize reverts even though
        // 1 second > 0 has passed.
        vm.warp(block.timestamp + 5);
        vm.expectRevert();
        attester.finalizeBatch(1);

        // After the full original window the snapshot lets finalize through.
        vm.warp(block.timestamp + CHALLENGE_WINDOW);
        attester.finalizeBatch(1);
        (,,,,, bool finalized,,) = attester.batches(1);
        assertTrue(finalized);
    }

    function test_FinalizeBatch_UsesProposeTimeChallengeWindow_HigherLater() public {
        // Propose with default 1h window, admin extends to 1 week.
        // The batch must still finalize on its original 1h, not on the
        // extended week — admin cannot retroactively freeze a batch.
        vm.prank(validator);
        attester.proposeBatch(1, keccak256("a"), 100);

        vm.prank(admin);
        attester.setChallengeWindow(7 days);

        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        attester.finalizeBatch(1);

        (,,,,, bool finalized,,) = attester.batches(1);
        assertTrue(finalized);
    }

    function test_SetChallengeWindow_RevertsOnZero() public {
        vm.prank(admin);
        vm.expectRevert(NoethrionAttester.InvalidChallengeWindow.selector);
        attester.setChallengeWindow(0);
    }

    function test_SetChallengeWindow_RevertsAboveUint64Max() public {
        uint256 tooBig = uint256(type(uint64).max) + 1;
        vm.prank(admin);
        vm.expectRevert(NoethrionAttester.InvalidChallengeWindow.selector);
        attester.setChallengeWindow(tooBig);
    }

    function test_SetTokenContract_RevertsOnNonContract() public {
        address eoa = makeAddr("not-a-contract");
        vm.prank(admin);
        vm.expectRevert(NoethrionAttester.NotAContract.selector);
        attester.setTokenContract(eoa);
    }

    // ───── Slash ─────

    function test_Slash_RevokesRole() public {
        bytes32 validatorRole = attester.VALIDATOR_ROLE();
        assertTrue(attester.hasRole(validatorRole, validator));

        vm.prank(admin);
        attester.slash(validator, keccak256("evidence"));

        assertFalse(attester.hasRole(validatorRole, validator));
    }

    function test_Slash_RecordsEvidence() public {
        bytes32 evidence = keccak256("conflict-sig-2026-05-13");
        vm.prank(admin);
        attester.slash(validator, evidence);

        assertEq(attester.slashEvidence(validator), evidence);
    }

    function test_Slash_OnlyAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        attester.slash(validator, keccak256("x"));
    }

    function test_Slash_RevertsOnZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(NoethrionAttester.ZeroAddress.selector);
        attester.slash(address(0), keccak256("x"));
    }

    function test_Slash_PreventsFurtherProposals() public {
        vm.prank(admin);
        attester.slash(validator, keccak256("x"));

        vm.prank(validator);
        vm.expectRevert();
        attester.proposeBatch(1, keccak256("a"), 100);
    }

    // ───── Claim ─────

    function _setupTwoLeafBatch()
        internal
        returns (bytes32 leafAlice, bytes32 leafBob, bytes32 root, bytes32[] memory proofForAlice)
    {
        leafAlice = keccak256(abi.encode(block.chainid, address(attester), alice, uint128(100 ether), uint64(1)));
        leafBob = keccak256(abi.encode(block.chainid, address(attester), bob, uint128(200 ether), uint64(1)));
        root = _hashPair(leafAlice, leafBob);

        vm.prank(validator);
        attester.proposeBatch(1, root, 300 ether);

        proofForAlice = new bytes32[](1);
        proofForAlice[0] = leafBob;
    }

    function test_Claim_Succeeds() public {
        (bytes32 leafAlice,, , bytes32[] memory proof) = _setupTwoLeafBatch();

        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        attester.finalizeBatch(1);

        attester.claim(uint64(1), proof, alice, uint128(100 ether));

        assertEq(token.balanceOf(alice), 100 ether);
        assertTrue(attester.claimed(leafAlice));
    }

    function test_Claim_RevertsOnDoubleClaim() public {
        (,, , bytes32[] memory proof) = _setupTwoLeafBatch();

        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        attester.finalizeBatch(1);

        attester.claim(uint64(1), proof, alice, uint128(100 ether));

        vm.expectRevert(
            abi.encodeWithSelector(
                NoethrionAttester.LeafAlreadyClaimed.selector,
                keccak256(abi.encode(block.chainid, address(attester), alice, uint128(100 ether), uint64(1)))
            )
        );
        attester.claim(uint64(1), proof, alice, uint128(100 ether));
    }

    function test_Claim_RevertsBeforeFinalization() public {
        (,, , bytes32[] memory proof) = _setupTwoLeafBatch();

        vm.expectRevert(
            abi.encodeWithSelector(NoethrionAttester.BatchNotFinalized.selector, uint64(1))
        );
        attester.claim(uint64(1), proof, alice, uint128(100 ether));
    }

    function test_Claim_RevertsOnInvalidProof() public {
        _setupTwoLeafBatch();

        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        attester.finalizeBatch(1);

        bytes32[] memory badProof = new bytes32[](1);
        badProof[0] = keccak256("not-a-real-sibling");

        vm.expectRevert(NoethrionAttester.InvalidMerkleProof.selector);
        attester.claim(uint64(1), badProof, alice, uint128(100 ether));
    }

    function test_Claim_RevertsOnTamperedAmount() public {
        (,, , bytes32[] memory proof) = _setupTwoLeafBatch();

        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        attester.finalizeBatch(1);

        vm.expectRevert(NoethrionAttester.InvalidMerkleProof.selector);
        attester.claim(uint64(1), proof, alice, uint128(999 ether));
    }

    function test_Claim_RevertsOnZeroBeneficiary() public {
        bytes32[] memory emptyProof = new bytes32[](0);
        vm.expectRevert(NoethrionAttester.ZeroAddress.selector);
        attester.claim(uint64(1), emptyProof, address(0), uint128(1 ether));
    }

    function test_Claim_RevertsOnZeroAmount() public {
        bytes32[] memory emptyProof = new bytes32[](0);
        vm.expectRevert(NoethrionAttester.ZeroAmount.selector);
        attester.claim(uint64(1), emptyProof, alice, 0);
    }

    function test_Claim_RevertsWhenTokenContractUnset() public {
        NoethrionAttester freshAttester = new NoethrionAttester(admin, CHALLENGE_WINDOW, DEFAULT_THRESHOLD);
        bytes32 validatorRole = freshAttester.VALIDATOR_ROLE();
        vm.prank(admin);
        freshAttester.grantRole(validatorRole, validator);

        bytes32 root = keccak256(abi.encode(block.chainid, address(freshAttester), alice, uint128(100 ether), uint64(1)));
        vm.prank(validator);
        freshAttester.proposeBatch(1, root, 100 ether);

        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        freshAttester.finalizeBatch(1);

        bytes32[] memory emptyProof = new bytes32[](0);
        vm.expectRevert(NoethrionAttester.TokenContractNotSet.selector);
        freshAttester.claim(uint64(1), emptyProof, alice, uint128(100 ether));
    }
}
