# ADR-004 — Swiss Stiftung as the Foundation legal structure

- **Status:** Accepted (target structure for Foundation incorporation in 2028+)
- **Date:** 2026-05-13
- **Deciders:** Founding contributors

## Context

Noethrion is administered by a Foundation that will own no commercial interest in the protocol, hold a small bootstrap treasury fixed at protocol genesis, certify hardware vendors, run a reference implementation, and resolve disputes when the community cannot. The Foundation's legal structure determines: (a) governance flexibility, (b) tax treatment of the bootstrap treasury, (c) regulatory exposure of the directors, (d) long-term durability across founder transitions, and (e) credibility with relying parties (utilities, regulators, large enterprises).

The decision space includes Swiss Stiftung, Liechtenstein Stiftung, US 501(c)(3) or 501(c)(6), Cayman Foundation Company, Marshall Islands DAO LLC, and Delaware C-Corp / LLC variants.

## Decision

Once the protocol stabilises and the bootstrap conditions are met, the Foundation will be incorporated as a **Swiss Stiftung** (Article 80–89 of the Swiss Civil Code).

In the interim — until the Foundation can credibly meet Stiftung administrative standards — protocol stewardship sits with a temporary Delaware C-Corp (the Initial Development Co.) which will self-dissolve upon Foundation incorporation and transfer assets to it.

## Consequences

**Positive**
- The Swiss Stiftung structure is the de-facto standard for global protocol foundations administering open standards. Linux Foundation has US presence but operates Linux Foundation Europe in Switzerland; the Web3 Foundation is a Swiss Stiftung; the Ethereum Foundation is a Swiss Stiftung. Relying parties recognise the structure.
- Swiss federal supervision (Eidgenössische Stiftungsaufsicht) provides external accountability that is difficult to fake. This raises the credibility ceiling for the Foundation's claims about governance, treasury management, and dispute resolution.
- Swiss banking, audit, and legal infrastructure for foundation work is mature and predictable. Costs are higher than offshore alternatives, but the operational predictability is worth the premium.
- Once the Stiftung's charter (Stiftungsurkunde) is filed and approved, **changing the charter is materially difficult by design**. This is a feature: it makes the Foundation's commitments — open license, no enterprise sales, no founder discretionary mints, treasury vesting schedule — credibly long-term.
- Tax treatment of the treasury allocation as a non-profit holding is well-understood under Swiss law. No equity-like obligations.

**Negative**
- Swiss incorporation is **expensive** by global comparison. Initial capital requirement, annual audit, and legal fees materially exceed US 501(c)(3) or Marshall Islands DAO LLC equivalents. The Foundation must reach a treasury maturity threshold before incorporation makes financial sense — hence the multi-year delay.
- Switzerland is a sovereign jurisdiction subject to its own regulatory shifts. We accept this risk as lower than the equivalent risk in any single alternative jurisdiction.
- Swiss federal regulators retain supervisory authority over the Stiftung. The Foundation's discretion is therefore bounded by Swiss public policy. We accept this bound as a feature rather than a bug.

## Alternatives considered

**US 501(c)(3) non-profit.** Lower setup cost, familiar to US contributors. Rejected as the primary structure because (a) US political exposure of crypto-adjacent projects is materially higher, (b) the IRS's evolving stance on protocol foundations is uncertain, (c) global relying parties associate US non-profits with US foreign policy in ways that complicate adoption.

**Marshall Islands DAO LLC.** Modern, crypto-aware. Rejected as the primary structure because the legal infrastructure (audit, banking, dispute resolution) is materially less mature than Switzerland's. The Marshall Islands form may, however, be appropriate for a token-governance entity nested under the Foundation, separate from the Foundation itself.

**Cayman Foundation Company.** Tax-neutral, popular in offshore crypto setups. Rejected because (a) reputational signalling to enterprise relying parties is weaker than Switzerland's, (b) the Foundation's posture is "credibility-maximising", not "tax-minimising".

**Liechtenstein Stiftung.** Similar to Swiss Stiftung but with lower minimum capital and faster setup. Rejected as the primary structure because Switzerland's deeper banking and audit infrastructure, plus the precedent set by Ethereum Foundation and Web3 Foundation, makes it the path of lower friction at the relevant scale.

**Delaware C-Corp / LLC (permanent).** The Initial Development Co. uses this structure now. Rejected as the *permanent* structure because for-profit corporate forms cannot credibly hold the protocol's open-standard commitments long-term.

## Open questions

- The treasury-maturity threshold at which Stiftung incorporation becomes financially sound — what dollar value of bootstrap treasury justifies the annual operating cost.
- The wind-down mechanics of the Initial Development Co. — asset transfer paperwork, employee continuity, IP assignment.
- Whether a Liechtenstein Stiftung intermediate structure makes sense as a stepping stone if treasury maturation takes longer than expected.
