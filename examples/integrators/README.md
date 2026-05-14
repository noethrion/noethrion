# Integrator templates

Drop-in starting points for the three most likely consumers of Noethrion attestations:

| File | Audience | When to use |
|------|----------|-------------|
| [`python_verifier_library.py`](./python_verifier_library.py) | Backend services in Python | You want to validate attestations server-side before granting access, awarding credit, or filing an audit report |
| [`javascript_verifier.ts`](./javascript_verifier.ts) | Node.js / TypeScript backends, edge functions | Same as above, JS ecosystem. No browser-DOM dependency — runs in Node, Workers, Lambda |
| [`solidity_consumer.sol`](./solidity_consumer.sol) | Another smart contract on the same chain | You want a downstream contract (DePIN reward pool, sustainability oracle, compliance gate) to act only when a Noethrion-attested kWh is presented |

Each file is **self-contained** — copy it into your project, install its (small) dependency set, edit the configuration constants, ship.

## Common dependencies

| Template | Runtime | Dependencies |
|----------|---------|--------------|
| Python | 3.10+ | `cryptography`, `pycryptodome` |
| TypeScript | Node 18+ | `@noble/curves`, `@noble/hashes` |
| Solidity | 0.8.24 | `@openzeppelin/contracts` (`MerkleProof`), the `NoethrionAttester` interface |

## Pattern shared across all three

Verifying a Noethrion attestation always involves the same four checks:

1. **Signature** — recover the device public key from the endorser registry; validate that the canonical payload was signed by it (ECDSA P-256, SHA-256).
2. **Merkle inclusion** — derive the leaf hash from `keccak256(abi.encode(block.chainid, address(attester), beneficiary, amount, epoch))`; the first two fields are the domain separator binding the leaf to a specific Attester instance on a specific chain, so a Merkle tree built for one deployment cannot be replayed against a fork or sibling deployment. Replay the sibling proof; confirm the derived root equals the on-chain committed root.
3. **Finalization** — confirm the batch's challenge window has passed without successful challenge (i.e., `batches(epoch).finalized == true` on the Attester contract).
4. **Use-case policy** — apply any caller-specific rules: timestamp freshness, jurisdiction, allow-listed beneficiaries, etc. This is outside the protocol; the templates leave it to you.

The three templates implement steps 1–3 directly and stop short of step 4 by design.

## What these are NOT

- Production-ready libraries with semver and CI. They are starter code. Treat them like the reference implementations on the IETF datatracker, not like `npm install some-package`.
- Replacement for the spec. When something is ambiguous, the [Internet-Draft](../../spec/noethrion-attestation-v0.1.md) is normative.
- A full endorsement-registry client. Each template assumes you have already obtained the device public key by some out-of-band path (configuration file, manual entry, your own registry lookup). The endorsement layer is operational policy and will live in a companion v0.2 spec.
