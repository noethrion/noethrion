// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title NoethrionConsumerExample
 * @notice Reference template — a downstream contract that gates access to a
 *         function behind proof of a Noethrion-attested kWh. Copy, edit the
 *         attester address, ship.
 *
 *         Illustrative use cases:
 *         - DePIN reward pool that pays out only to verified clean-energy nodes
 *         - Sustainability claim oracle that on-chain entities can query
 *         - Compliance gate that only routes orders backed by attested energy
 *
 *         The contract does NOT itself mint NOET — the protocol's own claim
 *         flow handles that. This template demonstrates how to **read** a
 *         Noethrion commitment and act on it.
 *
 *         For a richer example with role-based access, treasury management,
 *         or per-beneficiary state, extend from here.
 */

/// @dev Minimal slice of NoethrionAttester storage that consumers need.
interface INoethrionAttesterReader {
    function batches(uint64 epoch) external view returns (
        bytes32 merkleRoot,
        uint64 epochNum,
        uint128 totalKwh,
        uint64 timestamp,
        address proposer,
        bool finalized,
        uint64 thresholdAtPropose,
        uint64 challengeWindowAtPropose
    );
}

contract NoethrionConsumerExample {
    INoethrionAttesterReader public immutable attester;

    /// @notice Tracks which leaves a consumer has already redeemed.
    /// Independent of the Attester's own `claimed` mapping — that one prevents
    /// double-mint of NOET; this one prevents double-redemption inside YOUR app.
    mapping(bytes32 => bool) public redeemed;

    error BatchNotFinalized(uint64 epoch);
    error InvalidMerkleProof();
    error AlreadyRedeemed(bytes32 leaf);

    event KwhRedeemed(uint64 indexed epoch, address indexed beneficiary, uint128 amount, bytes32 indexed leaf);

    constructor(address attesterAddr) {
        attester = INoethrionAttesterReader(attesterAddr);
    }

    /**
     * @notice Redeem an attestation against this consumer's policy.
     *
     * Replace the body of `_applyPolicy()` below with whatever your
     * downstream logic should do once the kWh is verified — credit a balance,
     * mint a different token, emit a compliance receipt, gate a withdrawal.
     */
    function redeem(
        uint64 epoch,
        bytes32[] calldata proof,
        address beneficiary,
        uint128 amount
    ) external {
        // 1. Confirm the batch is finalized on the upstream Attester.
        (bytes32 root, , , , , bool finalized, , ) = attester.batches(epoch);
        if (!finalized) revert BatchNotFinalized(epoch);

        // 2. Re-derive the leaf the SAME way NoethrionAttester.claim() does.
        bytes32 leaf = keccak256(abi.encode(block.chainid, address(attester), beneficiary, amount, epoch));

        // 3. Verify Merkle inclusion against the on-chain committed root.
        if (!MerkleProof.verify(proof, root, leaf)) revert InvalidMerkleProof();

        // 4. Prevent double-redemption inside THIS consumer.
        if (redeemed[leaf]) revert AlreadyRedeemed(leaf);
        redeemed[leaf] = true;

        // 5. Apply your policy.
        _applyPolicy(beneficiary, amount, epoch);

        emit KwhRedeemed(epoch, beneficiary, amount, leaf);
    }

    /**
     * @dev Stub policy — replace with project-specific logic.
     *      Examples:
     *        - `myToken.transfer(beneficiary, amount * 2);`     // 2× reward
     *        - `balances[beneficiary] += amount;`                // accrue credit
     *        - `complianceLog[beneficiary].push(amount);`       // audit trail
     */
    function _applyPolicy(address beneficiary, uint128 amount, uint64 epoch) internal virtual {
        // intentionally empty in the template
    }
}
