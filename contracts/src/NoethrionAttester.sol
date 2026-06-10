// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/// @dev Minimal interface that the Attester needs from the NOET token contract.
interface INoethrionToken {
    function mint(address to, uint256 amount) external;
}

/**
 * @title NoethrionAttester
 * @notice Accepts Merkle roots representing batches of verified green-energy
 *         attestations from a quorum of off-chain validators. Each attestation
 *         corresponds to a measured kWh produced by a certified producer device.
 *         Mints NOET to the beneficiary upon successful claim against a
 *         finalized batch.
 *
 * @dev STATUS: v0.2 — production-leaning.
 *      Implemented in this version:
 *        - m-of-n threshold validator quorum (propose + vote + finalize)
 *        - Admin-triggered slashing with off-chain evidence reference
 *        - Per-epoch double-vote prevention
 *        - Per-batch snapshots of `threshold` and `challengeWindow` at propose
 *          time, so subsequent admin setThreshold / setChallengeWindow calls
 *          cannot retroactively change the quorum or unlock delay required to
 *          finalize an in-flight batch (the symmetric reviewer-finding closure
 *          for both H-3 and C-2)
 *
 *      Still pending for mainnet:
 *        - On-chain fraud proof verification feeding slash() automatically
 *          (currently admin-triggered with off-chain evidence)
 *        - Multi-sig admin to gate the slash() and setThreshold() powers
 *        - Cross-chain bridge integration
 *        - Comprehensive third-party audit
 *
 *      Leaf encoding: keccak256(abi.encode(block.chainid, address(this),
 *      beneficiary, amount, epoch)). The first two fields act as a
 *      domain separator binding each leaf to the specific Attester instance
 *      on the specific chain, so a Merkle tree built for one Attester cannot
 *      be replayed against a fork or a sibling deployment. Off-chain
 *      Merkle-tree builders MUST use the same encoding or claims will fail
 *      the InvalidMerkleProof check.
 *
 *      Merkle verification uses OpenZeppelin's MerkleProof, which hashes
 *      sibling pairs in sorted order (commutative). Builders MUST sort pairs
 *      when constructing the tree.
 *
 * @custom:security-contact security@noethrion.com
 */
contract NoethrionAttester is AccessControl, Pausable, ReentrancyGuard {
    // ─────────────────────────────────────────────────────────────────────────
    //  Roles
    // ─────────────────────────────────────────────────────────────────────────

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // ─────────────────────────────────────────────────────────────────────────
    //  Types
    // ─────────────────────────────────────────────────────────────────────────

    struct AttestationBatch {
        bytes32 merkleRoot;
        uint64 epoch;
        uint128 totalKwh;
        uint64 timestamp;
        address proposer;             // first validator to propose, also counts as first vote
        bool finalized;
        uint64 thresholdAtPropose;    // quorum required is fixed at propose time so later setThreshold cannot retroactively pass or block this batch
        uint64 challengeWindowAtPropose; // unlock delay is fixed at propose time so later setChallengeWindow cannot retroactively shrink (or extend) this batch's window
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Storage
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Address of the NoethrionToken contract authorized to be minted by this attester
    address public tokenContract;

    /// @notice Challenge window in seconds before a batch can be finalized
    /// @dev An on-chain challenge entry point is v0.3+ work. In v0.2 the
    ///      response to fraud detected during the window is pause() + slash().
    uint256 public challengeWindow;

    /// @notice m in m-of-n — number of distinct validator votes required for finalization
    uint256 public threshold;

    /// @notice Maps epoch number to its attestation batch
    mapping(uint64 => AttestationBatch) public batches;

    /// @notice Tracks which validators have voted on which epochs
    mapping(uint64 => mapping(address => bool)) public voted;

    /// @notice Number of distinct validator votes recorded for a given epoch
    mapping(uint64 => uint256) public voteCount;

    /// @notice Tracks claimed leaves to prevent double-spend
    mapping(bytes32 => bool) public claimed;

    /// @notice For each slashed validator, the off-chain evidence hash submitted at slash time
    mapping(address => bytes32) public slashEvidence;

    /// @notice Latest finalized epoch
    uint64 public latestEpoch;

    // ─────────────────────────────────────────────────────────────────────────
    //  Events
    // ─────────────────────────────────────────────────────────────────────────

    // Note: this event already uses the EVM's maximum of 3 indexed topics
    // (epoch, merkleRoot, proposer). Future additions to the payload must be
    // non-indexed (data slot) or one of the existing three must be dropped.
    event BatchProposed(
        uint64 indexed epoch,
        bytes32 indexed merkleRoot,
        uint128 totalKwh,
        address indexed proposer,
        uint64 thresholdAtPropose
    );
    event BatchVoted(uint64 indexed epoch, address indexed validator, uint256 newCount);
    event BatchFinalized(uint64 indexed epoch, bytes32 indexed merkleRoot);
    event AttestationClaimed(bytes32 indexed leaf, address indexed beneficiary, uint128 amount);
    event TokenContractUpdated(address indexed oldToken, address indexed newToken);
    event ChallengeWindowUpdated(uint256 oldWindow, uint256 newWindow);
    event ThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event ValidatorSlashed(address indexed validator, bytes32 evidenceHash, uint256 timestamp);

    // ─────────────────────────────────────────────────────────────────────────
    //  Errors
    // ─────────────────────────────────────────────────────────────────────────

    error EpochAlreadyProposed(uint64 epoch);
    error EpochNotFound(uint64 epoch);
    error BatchAlreadyFinalized(uint64 epoch);
    error BatchNotFinalized(uint64 epoch);
    error ChallengeWindowActive(uint64 epoch, uint256 unlocksAt);
    error InsufficientVotes(uint64 epoch, uint256 have, uint256 need);
    error AlreadyVoted(uint64 epoch, address validator);
    error LeafAlreadyClaimed(bytes32 leaf);
    error InvalidMerkleProof();
    error InvalidThreshold(uint256 threshold);
    error InvalidChallengeWindow();
    error TokenContractNotSet();
    error NotAContract();
    error ZeroAddress();
    error ZeroAmount();

    // ─────────────────────────────────────────────────────────────────────────
    //  Constructor
    // ─────────────────────────────────────────────────────────────────────────

    constructor(address admin, uint256 initialChallengeWindow, uint256 initialThreshold) {
        if (admin == address(0)) revert ZeroAddress();
        if (initialThreshold == 0 || initialThreshold > type(uint64).max) {
            revert InvalidThreshold(initialThreshold);
        }
        if (initialChallengeWindow == 0 || initialChallengeWindow > type(uint64).max) {
            revert InvalidChallengeWindow();
        }
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        challengeWindow = initialChallengeWindow;
        threshold = initialThreshold;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Validator API — propose + vote + finalize
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Propose a new attestation batch. The proposer's call also counts as
     *         their vote, so a batch with threshold=1 needs no further votes.
     * @dev `totalKwh` is informational (event/audit surface). The contract does
     *      not verify it against the Merkle leaves, and it does not cap how much
     *      can be minted via claim() for this batch — the hard on-chain supply
     *      bound is the token's MAX_SUPPLY.
     * @param epoch Sequential epoch number; first writer wins.
     * @param merkleRoot Root of the Merkle tree built off-chain by validator quorum.
     * @param totalKwh Total kWh attested in this batch (sum of all leaves).
     */
    function proposeBatch(uint64 epoch, bytes32 merkleRoot, uint128 totalKwh)
        external
        onlyRole(VALIDATOR_ROLE)
        whenNotPaused
    {
        if (batches[epoch].timestamp != 0) revert EpochAlreadyProposed(epoch);

        // Snapshot threshold + challengeWindow at propose time so subsequent
        // setThreshold / setChallengeWindow calls cannot retroactively change
        // the quorum or unlock delay required to finalize this batch. The
        // uint64 casts are safe because the constructor, setThreshold and
        // setChallengeWindow all revert on values that exceed the uint64 range.
        uint64 thresholdSnapshot = uint64(threshold);
        uint64 windowSnapshot = uint64(challengeWindow);
        batches[epoch] = AttestationBatch({
            merkleRoot: merkleRoot,
            epoch: epoch,
            totalKwh: totalKwh,
            timestamp: uint64(block.timestamp),
            proposer: msg.sender,
            finalized: false,
            thresholdAtPropose: thresholdSnapshot,
            challengeWindowAtPropose: windowSnapshot
        });

        // Proposer's submission counts as their vote.
        voted[epoch][msg.sender] = true;
        voteCount[epoch] = 1;

        emit BatchProposed(epoch, merkleRoot, totalKwh, msg.sender, thresholdSnapshot);
        emit BatchVoted(epoch, msg.sender, 1);
    }

    /**
     * @notice Add the caller's vote to an existing proposed batch. Must be a
     *         validator who has not already voted on this epoch.
     * @dev voteBatch is allowed at any time before the batch is finalized,
     *      including after the challenge window has elapsed. Late votes only
     *      affect the quorum check at finalize time; they cannot retroactively
     *      reopen a finalized batch.
     */
    function voteBatch(uint64 epoch) external onlyRole(VALIDATOR_ROLE) whenNotPaused {
        AttestationBatch storage batch = batches[epoch];
        if (batch.timestamp == 0) revert EpochNotFound(epoch);
        if (batch.finalized) revert BatchAlreadyFinalized(epoch);
        if (voted[epoch][msg.sender]) revert AlreadyVoted(epoch, msg.sender);

        voted[epoch][msg.sender] = true;
        uint256 newCount = voteCount[epoch] + 1;
        voteCount[epoch] = newCount;

        emit BatchVoted(epoch, msg.sender, newCount);
    }

    /**
     * @notice Finalize a batch after the challenge window expires and the
     *         threshold number of distinct validator votes has been recorded.
     */
    function finalizeBatch(uint64 epoch) external whenNotPaused {
        AttestationBatch storage batch = batches[epoch];
        if (batch.timestamp == 0) revert EpochNotFound(epoch);
        if (batch.finalized) revert BatchAlreadyFinalized(epoch);

        uint256 currentVotes = voteCount[epoch];
        uint256 requiredVotes = batch.thresholdAtPropose;
        if (currentVotes < requiredVotes) revert InsufficientVotes(epoch, currentVotes, requiredVotes);

        uint256 unlocksAt = uint256(batch.timestamp) + uint256(batch.challengeWindowAtPropose);
        if (block.timestamp < unlocksAt) revert ChallengeWindowActive(epoch, unlocksAt);

        batch.finalized = true;
        if (epoch > latestEpoch) latestEpoch = epoch;

        emit BatchFinalized(epoch, batch.merkleRoot);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Claim API
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Claim NOET tokens for a verified attestation leaf.
     * @param epoch Epoch number the leaf belongs to. The batch MUST be finalized.
     * @param proof Merkle inclusion proof — siblings along the path to the root.
     *              OpenZeppelin's MerkleProof.verify hashes pairs in sorted
     *              order; off-chain builders MUST match that convention.
     * @param beneficiary Recipient of the minted NOET.
     * @param amount NOET amount (18 decimals — wei-scale).
     * @dev The leaf is derived inside the contract from
     *      keccak256(abi.encode(block.chainid, address(this), beneficiary, amount, epoch)).
     *      block.chainid and address(this) act as a domain separator so a Merkle
     *      tree built for one Attester instance on one chain cannot be replayed
     *      against another Attester (or the same code on a different chain).
     *      Off-chain builders MUST include both values when constructing leaves.
     *      Double-spend prevention: each leaf hash is recorded in `claimed`
     *      before the mint call. Reentrancy guard wraps the external call.
     *      claim() is permissionless — anyone can call it on behalf of any
     *      beneficiary; the mint always goes to the `beneficiary` argument
     *      from the leaf, never to msg.sender. This lets gas relayers and
     *      indexer-driven aggregators redeem for end users without holding
     *      private keys.
     */
    function claim(uint64 epoch, bytes32[] calldata proof, address beneficiary, uint128 amount)
        external
        whenNotPaused
        nonReentrant
    {
        if (beneficiary == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (tokenContract == address(0)) revert TokenContractNotSet();

        AttestationBatch storage batch = batches[epoch];
        if (batch.timestamp == 0) revert EpochNotFound(epoch);
        if (!batch.finalized) revert BatchNotFinalized(epoch);

        bytes32 leaf = keccak256(abi.encode(block.chainid, address(this), beneficiary, amount, epoch));
        if (claimed[leaf]) revert LeafAlreadyClaimed(leaf);
        if (!MerkleProof.verify(proof, batch.merkleRoot, leaf)) revert InvalidMerkleProof();

        claimed[leaf] = true;
        emit AttestationClaimed(leaf, beneficiary, amount);

        // Mint AFTER state update — Checks-Effects-Interactions.
        // nonReentrant prevents same-call recursion; CEI ordering prevents
        // reentrancy state confusion if the token were to call back here.
        INoethrionToken(tokenContract).mint(beneficiary, amount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Admin
    //
    //  None of the admin functions below carry whenNotPaused. This is
    //  deliberate: when the contract is paused (an emergency-response
    //  state), admin must remain able to mutate parameters or revoke
    //  validator roles to actually fix the underlying incident. Pause
    //  gates the user-facing entry points (propose/vote/finalize/claim),
    //  not the admin's recovery surface.
    // ─────────────────────────────────────────────────────────────────────────

    function setTokenContract(address newToken) external onlyRole(ADMIN_ROLE) {
        if (newToken == address(0)) revert ZeroAddress();
        if (newToken.code.length == 0) revert NotAContract();
        emit TokenContractUpdated(tokenContract, newToken);
        tokenContract = newToken;
    }

    /**
     * @notice Update the challenge window for FUTURE proposals. Existing
     *         batches retain the window value snapshotted at propose time —
     *         see the AttestationBatch.challengeWindowAtPropose field. Must
     *         be > 0 and must fit in a uint64 so the per-batch snapshot is
     *         lossless. The uint64 ceiling tolerates challenge windows up to
     *         ~584 billion years, comfortably beyond any reasonable use.
     */
    function setChallengeWindow(uint256 newWindow) external onlyRole(ADMIN_ROLE) {
        if (newWindow == 0 || newWindow > type(uint64).max) revert InvalidChallengeWindow();
        emit ChallengeWindowUpdated(challengeWindow, newWindow);
        challengeWindow = newWindow;
    }

    /**
     * @notice Update the m-of-n threshold for FUTURE proposals. Existing batches
     *         retain the threshold value snapshotted at propose time — see the
     *         AttestationBatch.thresholdAtPropose field. Must be at least 1 and
     *         must fit in a uint64 so the per-batch snapshot is lossless.
     *         Operators are responsible for not setting threshold above the
     *         number of active validators — that condition would freeze new
     *         finalizations.
     */
    function setThreshold(uint256 newThreshold) external onlyRole(ADMIN_ROLE) {
        if (newThreshold == 0 || newThreshold > type(uint64).max) {
            revert InvalidThreshold(newThreshold);
        }
        emit ThresholdUpdated(threshold, newThreshold);
        threshold = newThreshold;
    }

    /**
     * @notice Slash a validator — revoke their VALIDATOR_ROLE and record an
     *         off-chain evidence hash for audit. Admin-triggered in v0.2;
     *         on-chain fraud proof verification is v0.3+ work.
     * @dev Known v0.2 limitation: slashing does not retract votes the
     *      validator has already cast, and there is no cancelBatch — a
     *      not-yet-finalized batch tainted by a slashed validator keeps its
     *      vote count. Mitigation: pause() blocks propose/vote/finalize/claim,
     *      so a tainted batch can be held unfinalized indefinitely while the
     *      incident is resolved. Vote retraction / batch cancellation is
     *      pre-mainnet (v0.3+) work.
     * @param validator Address losing the VALIDATOR_ROLE.
     * @param evidenceHash 32-byte hash of the off-chain misconduct evidence
     *                    (e.g., conflicting signatures, telemetry mismatch).
     *                    Stored permanently; subsequent slash() calls on the
     *                    same address will overwrite, so prefer including
     *                    evidence index or chained hash to track repeat events.
     */
    function slash(address validator, bytes32 evidenceHash) external onlyRole(ADMIN_ROLE) {
        if (validator == address(0)) revert ZeroAddress();
        _revokeRole(VALIDATOR_ROLE, validator);
        slashEvidence[validator] = evidenceHash;
        emit ValidatorSlashed(validator, evidenceHash, block.timestamp);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
}
