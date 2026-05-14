# ADR-003 — EVM-compatible Layer 2 as the settlement layer

- **Status:** Accepted
- **Date:** 2026-05-13
- **Deciders:** Founding contributors
- **Supersedes:** none

## Context

The protocol commits Merkle roots of attestation batches to a public ledger so anyone can independently verify a single attestation against the on-chain root. The choice of ledger affects: (a) gas cost per batch, (b) settlement finality time, (c) the ecosystem of tools available to verifiers and integrators, (d) regulatory exposure (some chains are politically associated with specific jurisdictions), and (e) long-term governance independence.

The decision sits between (1) Ethereum mainnet, (2) an EVM-compatible Layer 2 rollup, (3) a non-EVM smart-contract platform, and (4) a purpose-built Layer 1.

## Decision

The reference implementation commits Merkle roots to **an EVM-compatible Layer 2 rollup**. The specific rollup is not locked into the protocol specification at v0.1; selection criteria and the chosen rollup will be documented in a v0.2 companion document after a public criteria-based evaluation.

## Consequences

**Positive**
- Gas cost per batch is bounded at a fraction of a cent across major EVM L2s, making the per-attestation amortised cost negligible at 65,536 leaves per batch.
- EVM tooling ecosystem (Foundry, Hardhat, Etherscan-style explorers, MetaMask family wallets, OpenZeppelin libraries) is the most mature in the smart-contract world. Integrators can plug in with existing skills.
- Layer 2 rollups inherit Ethereum's security model for finality (modulo the rollup's own trust assumptions for sequencer behaviour). For an attestation primitive committing a Merkle root and waiting through a challenge window, this is more than sufficient.
- An L2 commitment can later be **mirrored** to other chains via cross-chain attestation bridges if multi-chain reach matters; the canonical root stays on the primary L2.

**Negative**
- Couples the protocol to Ethereum's broader trajectory. If Ethereum's roadmap diverges from what is needed (extreme gas spikes, governance instability, regulatory crackdown), the protocol's primary settlement layer comes under stress. We accept this risk because the alternatives are materially worse.
- The L2 ecosystem itself is in flux. Choosing a specific rollup at v0.1 would force a long-term lock-in based on incomplete information; deferring the choice to v0.2 is the right call.
- Non-EVM smart-contract platforms are largely excluded from the primary settlement role under this decision. Selective porting to alternative ecosystems remains possible at the application level.

## Alternatives considered

**Ethereum mainnet.** Highest security, broadest adoption. Rejected because gas costs at the protocol's projected commitment frequency are prohibitive. A future protocol revision MAY anchor periodic super-roots to mainnet for additional finality, but this is not the primary settlement path.

**A purpose-built Layer 1.** Maximum protocol sovereignty. Rejected because building, securing, and validator-bootstrapping a chain is roughly two years of full-time work that contributes nothing to the protocol's core problem. Past attempts in adjacent industries have a poor track record. The Foundation's resources are better spent on protocol design and ecosystem cultivation.

**Non-EVM smart-contract platforms.** Generally rejected because (a) the verifier ecosystem and the integrator ecosystem outside EVM is smaller, (b) the OpenZeppelin contracts we reuse for access control, Merkle proofs, and pausability are EVM-specific, and (c) we would be writing more reference code instead of fewer. Selective non-EVM deployment as a secondary path remains open.

**A purpose-built application chain on an alternative app-chain framework.** Considered. Rejected for v0.1 because the smaller verifier ecosystem outweighs the sovereignty benefit at this stage of the project. A later revision may revisit if alternative tooling for attestation use cases matures faster than EVM tooling.

## Open questions

- The specific Layer 2 rollup selected for v0.2 — pending the public criteria-based evaluation described above.
- Cross-chain mirroring strategy — whether attestation roots should be re-published periodically to other chains, and through what mechanism (canonical bridges, light-client proofs, or generic message-passing).
- Long-term super-root anchoring to a longer-finality settlement layer as an additional checkpoint mechanism — value, frequency, cost, and choice of target.
