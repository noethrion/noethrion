// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {NoethrionAttester} from "../src/NoethrionAttester.sol";
import {NoethrionToken} from "../src/NoethrionToken.sol";

/**
 * @dev Phase 2 handler — every batch is a 4-leaf Merkle tree with real proofs.
 *      Threshold is mutated by the fuzzer (bounded to a reachable range), so
 *      the quorum invariant has teeth. Leaf amounts are constructed to be
 *      strictly increasing within a batch, guaranteeing unique leaves.
 */
contract MultiLeafHandler is Test {
    NoethrionAttester public immutable attester;
    NoethrionToken public immutable token;
    address public immutable admin;

    uint256 public constant CHALLENGE_WINDOW = 1 hours;
    uint256 public constant VALIDATOR_COUNT = 5;
    uint256 public constant BENEFICIARY_COUNT = 4;
    uint256 public constant LEAVES_PER_BATCH = 4;

    address[VALIDATOR_COUNT] public validators;
    address[BENEFICIARY_COUNT] public beneficiaries;

    uint64 public epochCounter;

    // Ghost state — exposed to invariants.
    uint256 public ghostTotalClaimed;
    uint256 public ghostTotalFinalizedKwh;
    uint256 public ghostClaimSucceeded;
    uint256 public ghostFinalizeSucceeded;
    uint64 public ghostMaxFinalizedEpoch;

    struct BatchData {
        uint128 totalKwh;
        uint256 thresholdAtFinalize;
        bool finalized;
        bool exists;
    }

    mapping(uint64 => BatchData) public batchData;
    mapping(uint64 => mapping(uint256 => bool)) public leafClaimed;
    mapping(uint64 => mapping(uint256 => uint128)) public leafAmount;
    mapping(uint64 => mapping(uint256 => address)) public leafBeneficiary;

    constructor(NoethrionAttester _attester, NoethrionToken _token, address _admin) {
        attester = _attester;
        token = _token;
        admin = _admin;

        validators[0] = makeAddr("ph2-validator-0");
        validators[1] = makeAddr("ph2-validator-1");
        validators[2] = makeAddr("ph2-validator-2");
        validators[3] = makeAddr("ph2-validator-3");
        validators[4] = makeAddr("ph2-validator-4");

        beneficiaries[0] = makeAddr("ph2-beneficiary-0");
        beneficiaries[1] = makeAddr("ph2-beneficiary-1");
        beneficiaries[2] = makeAddr("ph2-beneficiary-2");
        beneficiaries[3] = makeAddr("ph2-beneficiary-3");
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    // ─── Action: propose a fresh 4-leaf batch ─────────────────────────────────

    function propose(uint256 vSeed, uint256 amtSeed) external {
        address v = validators[vSeed % VALIDATOR_COUNT];
        uint64 epoch = ++epochCounter;

        bytes32[LEAVES_PER_BATCH] memory leaves;
        uint128 totalKwh = 0;
        for (uint256 i = 0; i < LEAVES_PER_BATCH; i++) {
            // amt strictly increasing in i → leaves are guaranteed distinct
            // even when amtSeed is degenerate.
            uint128 amt = uint128(((amtSeed >> (i * 8)) % 1000) + (i + 1) * 10_000);
            address b = beneficiaries[i];
            leafAmount[epoch][i] = amt;
            leafBeneficiary[epoch][i] = b;
            totalKwh += amt;
            leaves[i] = keccak256(abi.encode(block.chainid, address(attester), b, amt, epoch));
        }
        bytes32 root = _hashPair(_hashPair(leaves[0], leaves[1]), _hashPair(leaves[2], leaves[3]));

        vm.prank(v);
        attester.proposeBatch(epoch, root, totalKwh);

        batchData[epoch] =
            BatchData({totalKwh: totalKwh, thresholdAtFinalize: 0, finalized: false, exists: true});
    }

    // ─── Action: cast an extra vote ───────────────────────────────────────────

    function vote(uint256 epochSeed, uint256 vSeed) external {
        if (epochCounter == 0) return;
        uint64 epoch = uint64(bound(epochSeed, 1, epochCounter));
        BatchData storage d = batchData[epoch];
        if (!d.exists || d.finalized) return;

        address v = validators[vSeed % VALIDATOR_COUNT];
        if (attester.voted(epoch, v)) return;

        vm.prank(v);
        attester.voteBatch(epoch);
    }

    // ─── Action: mutate threshold (bounded so quorum stays reachable) ─────────

    function setThreshold(uint256 t) external {
        t = bound(t, 1, VALIDATOR_COUNT);
        vm.prank(admin);
        attester.setThreshold(t);
    }

    // ─── Action: push to quorum, warp, finalize ───────────────────────────────

    function finalize(uint256 epochSeed) external {
        if (epochCounter == 0) return;
        uint64 epoch = uint64(bound(epochSeed, 1, epochCounter));
        BatchData storage d = batchData[epoch];
        if (!d.exists || d.finalized) return;

        uint256 needed = attester.threshold();
        for (uint256 i = 0; i < VALIDATOR_COUNT && attester.voteCount(epoch) < needed; i++) {
            if (!attester.voted(epoch, validators[i])) {
                vm.prank(validators[i]);
                attester.voteBatch(epoch);
            }
        }
        if (attester.voteCount(epoch) < needed) return; // somehow still short — bail

        (,,, uint64 ts,,,,) = attester.batches(epoch);
        uint256 unlocksAt = uint256(ts) + CHALLENGE_WINDOW;
        if (block.timestamp <= unlocksAt) vm.warp(unlocksAt + 1);

        attester.finalizeBatch(epoch);
        d.finalized = true;
        d.thresholdAtFinalize = needed;
        ghostTotalFinalizedKwh += d.totalKwh;
        ghostFinalizeSucceeded++;
        if (epoch > ghostMaxFinalizedEpoch) ghostMaxFinalizedEpoch = epoch;
    }

    // ─── Action: claim a specific leaf with a real Merkle proof ───────────────

    function claim(uint256 epochSeed, uint256 leafSeed) external {
        if (epochCounter == 0) return;
        uint64 epoch = uint64(bound(epochSeed, 1, epochCounter));
        BatchData storage d = batchData[epoch];
        if (!d.exists || !d.finalized) return;

        uint256 idx = leafSeed % LEAVES_PER_BATCH;
        if (leafClaimed[epoch][idx]) return;

        bytes32[LEAVES_PER_BATCH] memory leaves;
        for (uint256 i = 0; i < LEAVES_PER_BATCH; i++) {
            leaves[i] = keccak256(abi.encode(block.chainid, address(attester), leafBeneficiary[epoch][i], leafAmount[epoch][i], epoch));
        }
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = leaves[idx ^ 1]; // pair sibling: 0↔1, 2↔3
        proof[1] = idx < 2 ? _hashPair(leaves[2], leaves[3]) : _hashPair(leaves[0], leaves[1]);

        attester.claim(epoch, proof, leafBeneficiary[epoch][idx], leafAmount[epoch][idx]);
        leafClaimed[epoch][idx] = true;
        ghostTotalClaimed += leafAmount[epoch][idx];
        ghostClaimSucceeded++;
    }
}

contract NoethrionAttesterInvariantPhase2Test is Test {
    NoethrionAttester internal attester;
    NoethrionToken internal token;
    MultiLeafHandler internal handler;

    address internal admin = makeAddr("ph2-admin");

    function setUp() public {
        attester = new NoethrionAttester(admin, 1 hours, 1);
        token = new NoethrionToken(admin);
        handler = new MultiLeafHandler(attester, token, admin);

        bytes32 vRole = attester.VALIDATOR_ROLE();
        vm.startPrank(admin);
        for (uint256 i = 0; i < handler.VALIDATOR_COUNT(); i++) {
            attester.grantRole(vRole, handler.validators(i));
        }
        attester.setTokenContract(address(token));
        token.authorizeMinter(address(attester));
        vm.stopPrank();

        targetContract(address(handler));
    }

    /// @dev NOET total supply must equal the sum of successfully claimed leaf
    ///      amounts. Catches any unauthorized mint path or quantity drift in
    ///      Attester→Token plumbing.
    function invariant_TotalSupplyMatchesClaimed() public view {
        assertEq(token.totalSupply(), handler.ghostTotalClaimed(), "supply != claimed");
    }

    /// @dev Every finalized batch must, after the fact, still satisfy
    ///      voteCount >= thresholdAtFinalize. (voteCount is monotonic; the only
    ///      way this can break is if finalize() let a batch through under-quorum.)
    function invariant_FinalizedBatchesRetainQuorum() public view {
        uint64 max = handler.epochCounter();
        for (uint64 e = 1; e <= max; e++) {
            (, uint256 thresholdAtFinalize, bool finalized, bool exists) = handler.batchData(e);
            if (exists && finalized) {
                assertGe(attester.voteCount(e), thresholdAtFinalize, "quorum lost");
            }
        }
    }

    /// @dev Every leaf the handler observed claim() succeed on must show as
    ///      claimed in the contract's storage. Catches: silent failure to set
    ///      the claimed flag, which would enable double-spend.
    function invariant_ClaimedLeavesPersisted() public view {
        uint64 max = handler.epochCounter();
        uint256 leavesPerBatch = handler.LEAVES_PER_BATCH();
        for (uint64 e = 1; e <= max; e++) {
            for (uint256 i = 0; i < leavesPerBatch; i++) {
                if (handler.leafClaimed(e, i)) {
                    bytes32 leaf = keccak256(
                        abi.encode(
                            block.chainid,
                            address(attester),
                            handler.leafBeneficiary(e, i),
                            handler.leafAmount(e, i),
                            e
                        )
                    );
                    assertTrue(attester.claimed(leaf), "claimed flag missing");
                }
            }
        }
    }

    /// @dev latestEpoch must cover every epoch the handler has seen finalized.
    function invariant_LatestEpochCoversAllFinalized() public view {
        assertGe(attester.latestEpoch(), handler.ghostMaxFinalizedEpoch());
    }
}
