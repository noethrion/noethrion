// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {NoethrionAttester} from "../src/NoethrionAttester.sol";
import {NoethrionToken} from "../src/NoethrionToken.sol";

/**
 * @dev Phase 3 handler — extends phase 2's multi-leaf model with pause toggle.
 *      Every mutating action wraps the underlying call in try/catch so a
 *      successful execution while paused can be observed and counted.
 *      A successful state-change while `paused == true` is a critical bug,
 *      so the invariant pins that count at zero.
 */
contract PauseAwareHandler is Test {
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

    uint256 public ghostTotalClaimed;
    uint256 public ghostPausedMutationSucceeded; // MUST stay at 0
    uint256 public ghostPauseToggles;
    uint256 public ghostClaimSucceeded;

    struct BatchData {
        uint128 totalKwh;
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

        validators[0] = makeAddr("ph3-validator-0");
        validators[1] = makeAddr("ph3-validator-1");
        validators[2] = makeAddr("ph3-validator-2");
        validators[3] = makeAddr("ph3-validator-3");
        validators[4] = makeAddr("ph3-validator-4");

        beneficiaries[0] = makeAddr("ph3-beneficiary-0");
        beneficiaries[1] = makeAddr("ph3-beneficiary-1");
        beneficiaries[2] = makeAddr("ph3-beneficiary-2");
        beneficiaries[3] = makeAddr("ph3-beneficiary-3");
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    // ─── Admin: toggle pause/unpause ──────────────────────────────────────────

    function togglePause(uint256 seed) external {
        ghostPauseToggles++;
        if (seed % 2 == 0) {
            if (!attester.paused()) {
                vm.prank(admin);
                attester.pause();
            }
        } else {
            if (attester.paused()) {
                vm.prank(admin);
                attester.unpause();
            }
        }
    }

    // ─── Mutating actions wrapped in try/catch ────────────────────────────────

    function propose(uint256 vSeed, uint256 amtSeed) external {
        address v = validators[vSeed % VALIDATOR_COUNT];
        uint64 epoch = epochCounter + 1;

        bytes32[LEAVES_PER_BATCH] memory leaves;
        uint128 totalKwh = 0;
        uint128[LEAVES_PER_BATCH] memory amts;
        for (uint256 i = 0; i < LEAVES_PER_BATCH; i++) {
            uint128 amt = uint128(((amtSeed >> (i * 8)) % 1000) + (i + 1) * 10_000);
            amts[i] = amt;
            totalKwh += amt;
            leaves[i] = keccak256(abi.encode(block.chainid, address(attester), beneficiaries[i], amt, epoch));
        }
        bytes32 root = _hashPair(_hashPair(leaves[0], leaves[1]), _hashPair(leaves[2], leaves[3]));

        bool wasPaused = attester.paused();
        vm.prank(v);
        try attester.proposeBatch(epoch, root, totalKwh) {
            if (wasPaused) ghostPausedMutationSucceeded++;
            epochCounter = epoch;
            for (uint256 i = 0; i < LEAVES_PER_BATCH; i++) {
                leafAmount[epoch][i] = amts[i];
                leafBeneficiary[epoch][i] = beneficiaries[i];
            }
            batchData[epoch] = BatchData({totalKwh: totalKwh, finalized: false, exists: true});
        } catch {
            // expected when paused or otherwise reverting; nothing to record
        }
    }

    function vote(uint256 epochSeed, uint256 vSeed) external {
        if (epochCounter == 0) return;
        uint64 epoch = uint64(bound(epochSeed, 1, epochCounter));
        BatchData storage d = batchData[epoch];
        if (!d.exists || d.finalized) return;
        address v = validators[vSeed % VALIDATOR_COUNT];
        if (attester.voted(epoch, v)) return;

        bool wasPaused = attester.paused();
        vm.prank(v);
        try attester.voteBatch(epoch) {
            if (wasPaused) ghostPausedMutationSucceeded++;
        } catch {}
    }

    function finalize(uint256 epochSeed) external {
        if (epochCounter == 0) return;
        uint64 epoch = uint64(bound(epochSeed, 1, epochCounter));
        BatchData storage d = batchData[epoch];
        if (!d.exists || d.finalized) return;

        // Make sure threshold can be met — vote through remaining validators when unpaused.
        if (!attester.paused()) {
            uint256 needed = attester.threshold();
            for (uint256 i = 0; i < VALIDATOR_COUNT && attester.voteCount(epoch) < needed; i++) {
                if (!attester.voted(epoch, validators[i])) {
                    vm.prank(validators[i]);
                    try attester.voteBatch(epoch) {} catch {}
                }
            }
        }

        (,,, uint64 ts,,,,) = attester.batches(epoch);
        uint256 unlocksAt = uint256(ts) + CHALLENGE_WINDOW;
        if (block.timestamp <= unlocksAt) vm.warp(unlocksAt + 1);

        bool wasPaused = attester.paused();
        try attester.finalizeBatch(epoch) {
            if (wasPaused) ghostPausedMutationSucceeded++;
            d.finalized = true;
        } catch {}
    }

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
        proof[0] = leaves[idx ^ 1];
        proof[1] = idx < 2 ? _hashPair(leaves[2], leaves[3]) : _hashPair(leaves[0], leaves[1]);

        bool wasPaused = attester.paused();
        try attester.claim(epoch, proof, leafBeneficiary[epoch][idx], leafAmount[epoch][idx]) {
            if (wasPaused) ghostPausedMutationSucceeded++;
            leafClaimed[epoch][idx] = true;
            ghostTotalClaimed += leafAmount[epoch][idx];
            ghostClaimSucceeded++;
        } catch {}
    }
}

contract NoethrionAttesterInvariantPhase3Test is Test {
    NoethrionAttester internal attester;
    NoethrionToken internal token;
    PauseAwareHandler internal handler;

    address internal admin = makeAddr("ph3-admin");

    function setUp() public {
        attester = new NoethrionAttester(admin, 1 hours, 1);
        token = new NoethrionToken(admin);
        handler = new PauseAwareHandler(attester, token, admin);

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

    /// @dev While `paused == true`, no mutating user-facing action
    ///      (propose / vote / finalize / claim) may succeed. Each handler
    ///      action records the pre-call paused state and bumps a counter on
    ///      successful execution under pause — the counter must stay at zero.
    function invariant_PauseBlocksMutations() public view {
        assertEq(handler.ghostPausedMutationSucceeded(), 0, "mutation succeeded while paused");
    }

    /// @dev Re-prove the strongest phase-2 property under pause churn:
    ///      the supply→claimed equality must hold regardless of how many
    ///      pause toggles or failed-mid-claim attempts the fuzzer makes.
    function invariant_SupplyMatchesClaimedUnderPauseChurn() public view {
        assertEq(token.totalSupply(), handler.ghostTotalClaimed(), "supply drift under pause churn");
    }
}
