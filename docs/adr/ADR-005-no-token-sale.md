# ADR-005 — No ICO, presale, or private allocation rounds

- **Status:** Accepted (permanent)
- **Date:** 2026-05-13
- **Deciders:** Founding contributors

## Context

NOET is the protocol's unit of accounting — one NOET represents one verified kilowatt-hour. A token of this kind has multiple plausible distribution paths. The choice fixes the project's economic posture: whether NOET is a financial instrument or an attestation token, who can credibly use the protocol, and what regulatory exposure the Foundation carries.

The decision space includes (1) ICO / public token sale, (2) private allocation round to early investors, (3) presale to existing crypto holders, (4) gradual issuance via the protocol's normal claim mechanism only, and (5) airdrop to specific communities.

## Decision

The Foundation will **not conduct an ICO, presale, private allocation round, or any pre-protocol sale of NOET**, ever. The only mechanism by which NOET enters circulation is the protocol's own algorithmic emission rule: one NOET minted per verified kilowatt-hour committed on-chain. No human discretion modifies emission.

The Foundation's bootstrap treasury (5% of total NOET supply, vested over four years) is fixed at protocol genesis. It is not raised, sold, or allocated through any market process.

This decision is recorded as **permanent** in the sense that reversing it would require amending the Foundation's Stiftung charter — a high-friction process by design.

## Consequences

**Positive**
- Removes the protocol from the **securities-law exposure** that historically attached to token sales in major jurisdictions. There is no purchaser whose investment expectation depends on managerial efforts of the issuer, because there is no purchaser and there is no issuer-as-promoter.
- Removes the **early-investor capture** failure mode that has degraded prior crypto-and-energy projects. Insider allocations create misaligned incentives between token holders and protocol adopters from day one; we choose to skip the failure mode entirely.
- Makes the Foundation's posture **credibly long-term**. A Foundation that has not raised against future token issuance has no investor base to which it owes operational urgency; it can move at the speed appropriate for an infrastructure standard, which is slow.
- Aligns NOET with the closer organisational analogues — domain names, X.509 certificates, DNS records — which gain utility from issuance against real-world events, not market speculation.
- Closes the door on a class of contributor disputes (vesting disagreements, founder allocation second-guessing, allocation-round insider claims) before they can arise.

**Negative**
- Forecloses the **fast-bootstrap-via-token-sale path** that is the dominant funding model in adjacent crypto-and-energy projects. The Foundation must fund operations through grants, treasury, and (eventually) member dues — slower paths.
- Reduces short-term founder financial upside relative to a token-sale path. We treat this as desirable rather than as a cost: the Foundation must outlive its founders' financial interest.
- Some integrators may be slower to engage because there is no obvious financial pre-position they can take. We accept this as a filter — the integrators who engage anyway are the ones we want.

## Alternatives considered

**Conventional ICO.** Sells tokens to the public at protocol launch. Rejected primarily for securities-law exposure and historical track record of equivalent designs degrading post-launch.

**Private allocation round (VC-style).** Sells tokens at a discount to selected investors before public availability. Rejected because (a) creates the same misaligned-incentive failure mode as ICOs at smaller scale, (b) compromises the Foundation's claim to neutral standards stewardship, (c) introduces information asymmetries that contaminate downstream market behaviour.

**Retroactive airdrop to early contributors.** Awards NOET to wallets meeting eligibility criteria after launch. Rejected for v0.1 because (a) any criteria the Foundation defines becomes itself a politically contested object, (b) it conflicts with the "no human discretion modifies emission" principle, (c) it creates an attractive target for Sybil pressure.

**Liquidity Bootstrapping Pool (LBP) without sale.** A market-discovery mechanism where the Foundation deposits tokens against a price-discovery curve but does not directly receive proceeds. Rejected for the same reasons as the ICO: regardless of mechanism, any path that places NOET on a market before genuine attestation utility exists creates speculative pressure that distorts the protocol's adoption curve.

## Open questions

- How to handle eventual **secondary-market liquidity** for relying parties that legitimately need to transfer accumulated NOET. The protocol does not provide a venue; secondary venues will emerge organically. The Foundation's posture toward those venues is to be neutral.
- Whether to formalise the no-sale commitment in a **public covenant** beyond the Stiftung charter — for example a binding statement signed by the Founding contributors, published in the repository.
- Whether other auxiliary tokens (governance tokens, certification tokens) might be appropriate. The current answer is no, but a future ADR may revisit if the certification authority layer requires its own primitive.
