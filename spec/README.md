# `spec/` — Protocol specifications

This directory hosts the formal Noethrion protocol specifications. The lead document is the **Internet-Draft** that defines the attestation token format, the signature scheme, the Merkle aggregation and settlement design, and the threat model.

## Documents

| File | Status | Description |
|------|--------|-------------|
| [`noethrion-attestation-v0.1.md`](./noethrion-attestation-v0.1.md) | Draft v0.1 (2026-05-11) | Hardware-rooted attestation tokens for electricity generation. Aligned with RATS architecture ([RFC 9334](https://www.rfc-editor.org/rfc/rfc9334)) and the Entity Attestation Token format ([RFC 9711](https://www.rfc-editor.org/rfc/rfc9711)). Intended for submission to the IETF RATS WG after one further public-review iteration. |

## Reading order

1. **First-time readers**: start with [`../README.md`](../README.md) for the project overview and the technical summary, then [`../docs/whitepaper.html`](../docs/whitepaper.html) for the long-form motivation and economic design.
2. **Implementers**: read `noethrion-attestation-v0.1.md` end-to-end. The reference firmware in [`../firmware/`](../firmware/) and smart contracts in [`../contracts/`](../contracts/) implement what the I-D specifies.
3. **Reviewers**: critical feedback is the primary ask. Sections 8 (Threat Model) and 9 (Privacy Considerations) are the highest-priority targets for review. Please open a GitHub Discussion or email `team@noethrion.com`.

## Out-of-scope (will be specified in companion documents)

- **Token economics** (NOET issuance schedule, treasury allocation, vesting) — see [`../docs/constitution.html`](../docs/constitution.html).
- **Foundation governance** (Builders House, Council, dispute resolution) — see Constitution.
- **Hardware certification process** (Endorser onboarding, certification-batch revocation) — companion I-D planned for v0.2.
- **Post-quantum migration** (P-256 → ML-DSA) — covered in Section 5.2 of v0.1 as forward statement; full migration procedure deferred to a follow-up document.

## Change history

The IETF Internet-Draft version label (currently `v0.1`) is the draft revision number per IETF convention, not a protocol version. It will increment with each public-review iteration before WG submission. The Noethrion protocol's own version (currently aligned with the v0.2 reference contract) tracks the contract surface and is documented in the top-level `CHANGELOG.md`.

- **v0.1 (2026-05-11, extended 2026-05-13)** — initial IETF Internet-Draft. ES256 signature scheme over the NIST P-256 curve, SHA-256 Merkle aggregation, RATS architectural mapping ([RFC 9334](https://www.rfc-editor.org/rfc/rfc9334)), EAT-compatibility notes ([RFC 9711](https://www.rfc-editor.org/rfc/rfc9711)), IANA registration request for `application/noethrion+cbor`. **2026-05-13 extension:** Section 8.4 expanded to describe the m-of-n validator quorum (`proposeBatch` + `voteBatch` + `finalizeBatch`) and admin-triggered slashing, which were added to the reference contract as v0.2. **2026-05-13 second extension:** Section 6.2 commitment-record requirement extended to include the two propose-time snapshots (`thresholdAtPropose` and `challengeWindowAtPropose`) that close the symmetric retroactive-shift class of admin abuses; Section 3.5 added (Validator role definition). The protocol mechanism is now normative in the I-D; the v0.3 protocol extension will move slashing from admin-triggered to fraud-proof-verified.
