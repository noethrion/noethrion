# Noethrion — Project Context for Contributors

## What this is
Open standard for hardware-attested verification of clean energy generation.
1 NOET = 1 verified kWh, signed at hardware level by ECDSA P-256 secure elements.

## Tech stack
- Smart contracts: Solidity, Foundry, EVM Layer 2 settlement
- Hardware: ESP32 + ATECC608B (Phase 5 shipped, probe-only stub — see firmware/README.md)
- Spec: IETF I-D draft v0.1 ready for RATS WG submission (Phase 4 shipped — see spec/)

## Repository structure
- contracts/    Foundry-based smart contracts
- docs/         Whitepaper, Constitution, Brand Book
- assets/       Logos, brand assets
- firmware/     Hardware POC (in design)
- spec/         Protocol specifications (in design)

## Brand
See docs/brand-book-v0.3.html for full brand guidelines (colors, typography, logo usage, contact).

Logo: D2 series in assets/logos/D/

## Commit conventions
- Conventional commits format (feat: / fix: / docs: / etc)
- All commits to main require GPG signing
- See CONTRIBUTING.md for full guidelines

## Contact
- Email: team@noethrion.com
- Discussions: github.com/noethrion/noethrion/discussions
- Security: security@noethrion.com (see SECURITY.md)
