# Noethrion Smart Contracts

Foundry-based reference implementation of the Noethrion protocol on-chain components.

## Status

🟡 **v0.2 — production-leaning, pre-audit.** Core protocol surface is
implemented and tested (validator quorum, slashing, Merkle-proof claim,
reentrancy-guarded mint). Mainnet deployment remains gated on independent
third-party audit and protocol spec finalization.

## Contracts

| Contract | Purpose |
|---|---|
| `NoethrionAttester.sol` | Accepts Merkle roots of attested kWh batches from validator quorum |
| `NoethrionToken.sol` | ERC-20 token (NOET) — 1 token = 1 verified kWh, minted only by attester |

## Setup

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install dependencies
forge install OpenZeppelin/openzeppelin-contracts --no-commit
forge install foundry-rs/forge-std --no-commit

# Build
forge build

# Test
forge test -vvv

# Format
forge fmt
```

## Architecture (high-level)

```
   ┌────────────────────┐  proposeBatch + voteBatch  ┌─────────────────────┐
   │  Validator Quorum  │ ─────────────────────────▶ │  NoethrionAttester  │
   │   (on-chain m-of-n)│                            │   (on-chain root DB)│
   └────────────────────┘                            └──────────┬──────────┘
                                                                │ mint()
                                                                ▼
                                                    ┌──────────────────────┐
                                                    │   NoethrionToken     │
                                                    │   (ERC-20, NOET)     │
                                                    └──────────────────────┘
```

## Roadmap (post-v0.2)

Shipped in v0.2:
- ✅ m-of-n threshold validator quorum via on-chain propose+vote (ADR-006)
- ✅ Admin-triggered slashing with off-chain evidence reference
- ✅ Merkle proof verification in `claim()` (OpenZeppelin `MerkleProof`)
- ✅ ReentrancyGuard around the external mint call

Remaining for mainnet:
- [ ] Full third-party audit (Trail of Bits / OpenZeppelin / Spearbit)
- [ ] On-chain fraud-proof verification feeding `slash()` automatically (v0.3+)
- [ ] Multi-sig admin gate on `slash()` + `setThreshold()` (v0.3+)
- [ ] Cross-chain bridge integration
- [ ] Bug bounty (Immunefi)
- [ ] Formal verification of supply invariants (Certora / Halmos)

## Security

See [../SECURITY.md](../SECURITY.md). Disclosure: security@noethrion.com
