# Architecture Decision Records

Lightweight write-ups of the foundational design choices in Noethrion. Format follows [MADR](https://adr.github.io/madr/) — each ADR is a short note covering Context (what problem), Decision (what we chose), Consequences (what it implies), and Alternatives Considered (what we rejected and why).

ADRs are immutable once accepted. Subsequent changes are recorded as new ADRs that supersede prior ones — never by editing accepted ADRs in place.

## Index

| # | Title | Status |
|---|-------|--------|
| [ADR-001](./ADR-001-signature-curve-p256.md) | Use ECDSA P-256 as the device signature scheme | Accepted (2026-05) |
| [ADR-002](./ADR-002-hardware-root-of-trust.md) | Hardware-rooted attestation as the trust foundation | Accepted (2026-05) |
| [ADR-003](./ADR-003-evm-l2-settlement.md) | EVM-compatible Layer 2 as the settlement layer | Accepted (2026-05) |
| [ADR-004](./ADR-004-swiss-stiftung-foundation.md) | Swiss Stiftung as the Foundation legal structure | Accepted (2026-05) |
| [ADR-005](./ADR-005-no-token-sale.md) | No ICO / presale / private allocation rounds | Accepted (2026-05) |
| [ADR-006](./ADR-006-threshold-submitter.md) | m-of-n validator quorum via on-chain propose + vote | Accepted (2026-05) |
| [ADR-007](./ADR-007-production-admin-multisig.md) | Production admin uses Safe multi-sig with timelock on slash and setThreshold | Accepted (2026-05) |

## When to add a new ADR

When a decision is **significant** (touches the protocol design, the Foundation structure, or the economic model), **directional** (changes the trajectory of the project, not just a tactical implementation choice), and **expected to outlive its author** (a future contributor will need to know why). Trivial choices (file layouts, code style, library versions) do not warrant an ADR.

## Cross-references

- [`spec/noethrion-attestation-v0.1.md`](../../spec/noethrion-attestation-v0.1.md) — normative protocol specification
- [`docs/whitepaper.html`](../whitepaper.html) — long-form motivation
- [`docs/constitution.html`](../constitution.html) — Foundation governance and token economics
- [`FAQ.md`](../../FAQ.md) — accessible summaries of several decisions documented here
