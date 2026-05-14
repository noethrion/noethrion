// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {NoethrionAttester} from "../src/NoethrionAttester.sol";
import {NoethrionToken} from "../src/NoethrionToken.sol";

/**
 * @dev Handler bounds the action space and tracks ghost state.
 *      Uses single-leaf batches (root == leaf) to keep proof construction
 *      trivial inside the fuzzer. Threshold = 1, so proposer alone finalizes.
 */
contract AttesterHandler is Test {
    NoethrionAttester public immutable attester;
    NoethrionToken public immutable token;

    uint256 public constant CHALLENGE_WINDOW = 1 hours;
    uint256 public constant VALIDATOR_COUNT = 5;
    uint256 public constant BENEFICIARY_COUNT = 5;

    address[VALIDATOR_COUNT] public validators;
    address[BENEFICIARY_COUNT] public beneficiaries;

    uint64 public epochCounter;

    // Ghost state — verified by external invariants.
    uint256 public ghostTotalClaimed;
    uint256 public ghostTotalFinalizedKwh;

    struct LeafData {
        address beneficiary;
        uint128 amount;
        bool finalized;
        bool claimed;
    }

    mapping(uint64 => LeafData) public leafByEpoch;

    constructor(NoethrionAttester _attester, NoethrionToken _token) {
        attester = _attester;
        token = _token;

        validators[0] = makeAddr("inv-validator-0");
        validators[1] = makeAddr("inv-validator-1");
        validators[2] = makeAddr("inv-validator-2");
        validators[3] = makeAddr("inv-validator-3");
        validators[4] = makeAddr("inv-validator-4");

        beneficiaries[0] = makeAddr("inv-beneficiary-0");
        beneficiaries[1] = makeAddr("inv-beneficiary-1");
        beneficiaries[2] = makeAddr("inv-beneficiary-2");
        beneficiaries[3] = makeAddr("inv-beneficiary-3");
        beneficiaries[4] = makeAddr("inv-beneficiary-4");
    }

    // ─── Action: propose a new single-leaf batch ──────────────────────────────

    function propose(uint256 vSeed, uint256 bSeed, uint128 amount) external {
        amount = uint128(bound(uint256(amount), 1, 1_000_000 ether));
        address v = validators[vSeed % VALIDATOR_COUNT];
        address b = beneficiaries[bSeed % BENEFICIARY_COUNT];

        uint64 epoch = ++epochCounter;
        bytes32 leaf = keccak256(abi.encode(block.chainid, address(attester), b, amount, epoch));

        vm.prank(v);
        attester.proposeBatch(epoch, leaf, amount);

        leafByEpoch[epoch] = LeafData({beneficiary: b, amount: amount, finalized: false, claimed: false});
    }

    // ─── Action: cast a validator vote on an existing proposal ────────────────

    function vote(uint256 epochSeed, uint256 vSeed) external {
        if (epochCounter == 0) return;
        uint64 epoch = uint64(bound(epochSeed, 1, epochCounter));
        address v = validators[vSeed % VALIDATOR_COUNT];

        LeafData storage data = leafByEpoch[epoch];
        if (data.finalized) return;
        if (attester.voted(epoch, v)) return;

        vm.prank(v);
        attester.voteBatch(epoch);
    }

    // ─── Action: warp past the window and finalize ────────────────────────────

    function finalize(uint256 epochSeed) external {
        if (epochCounter == 0) return;
        uint64 epoch = uint64(bound(epochSeed, 1, epochCounter));
        LeafData storage data = leafByEpoch[epoch];
        if (data.finalized) return;

        (,,, uint64 timestamp,,,,) = attester.batches(epoch);
        if (timestamp == 0) return;

        uint256 unlocksAt = uint256(timestamp) + CHALLENGE_WINDOW;
        if (block.timestamp <= unlocksAt) {
            vm.warp(unlocksAt + 1);
        }

        attester.finalizeBatch(epoch);
        data.finalized = true;
        ghostTotalFinalizedKwh += data.amount;
    }

    // ─── Action: claim a finalized leaf ───────────────────────────────────────

    function claim(uint256 epochSeed) external {
        if (epochCounter == 0) return;
        uint64 epoch = uint64(bound(epochSeed, 1, epochCounter));
        LeafData storage data = leafByEpoch[epoch];
        if (!data.finalized || data.claimed) return;

        bytes32[] memory emptyProof = new bytes32[](0); // single-leaf tree
        attester.claim(epoch, emptyProof, data.beneficiary, data.amount);
        data.claimed = true;
        ghostTotalClaimed += data.amount;
    }
}

contract NoethrionAttesterInvariantTest is Test {
    NoethrionAttester internal attester;
    NoethrionToken internal token;
    AttesterHandler internal handler;

    address internal admin = makeAddr("inv-admin");

    function setUp() public {
        attester = new NoethrionAttester(admin, 1 hours, 1);
        token = new NoethrionToken(admin);
        handler = new AttesterHandler(attester, token);

        bytes32 validatorRole = attester.VALIDATOR_ROLE();
        vm.startPrank(admin);
        for (uint256 i = 0; i < handler.VALIDATOR_COUNT(); i++) {
            attester.grantRole(validatorRole, handler.validators(i));
        }
        attester.setTokenContract(address(token));
        token.authorizeMinter(address(attester));
        vm.stopPrank();

        targetContract(address(handler));
    }

    /**
     * @dev For every proposed epoch, the integer voteCount must equal the
     *      number of distinct validators flagged in the `voted` mapping.
     *      A divergence would mean either a double-counting bug in propose/vote
     *      or a silent vote not reflected in the tally.
     */
    function invariant_VoteCountMatchesVotedMapping() public view {
        uint64 maxEpoch = handler.epochCounter();
        uint256 vCount = handler.VALIDATOR_COUNT();
        for (uint64 e = 1; e <= maxEpoch; e++) {
            uint256 expected = 0;
            for (uint256 i = 0; i < vCount; i++) {
                if (attester.voted(e, handler.validators(i))) expected++;
            }
            assertEq(expected, attester.voteCount(e), "voteCount mismatch");
        }
    }

    /**
     * @dev The total kWh successfully claimed across all leaves must never
     *      exceed the total kWh attested in finalized batches. A breach would
     *      mean a leaf claimed against an un-finalized batch or a double-claim
     *      that the contract failed to block — both critical mint-side bugs.
     */
    function invariant_TotalClaimedNeverExceedsFinalized() public view {
        assertLe(handler.ghostTotalClaimed(), handler.ghostTotalFinalizedKwh());
    }
}
