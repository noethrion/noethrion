#!/usr/bin/env python3
"""03 · Build a sorted-pair keccak256 Merkle tree over a synthetic batch.

The leaf encoding matches NoethrionAttester.claim() exactly:

    leaf = keccak256(abi.encode(
        block.chainid,
        address(attester),    // the deployed NoethrionAttester contract
        beneficiary,
        amount,
        epoch,
    ))

The first two fields are the domain separator — a Merkle tree built for one
Attester on one chain is byte-different from a leaf with the same
(beneficiary, amount, epoch) on any other deployment. The script reads
`CHAIN_ID` and `ATTESTER` from the environment so the builder always
produces leaves valid against a specific deployed contract.

The pair-hash convention matches OpenZeppelin MerkleProof (commutative — pairs
are sorted before hashing). This means proofs generated here verify directly
against the on-chain contract.

Output: examples/lifecycle/batch.json
    {
      "epoch":     <uint>,
      "totalKwh":  <uint>,
      "root":      "0x...",
      "leaves":    [{"beneficiary": "0x...", "amount": ..., "leaf": "0x...", "proof": [...]}],
    }

The script uses pycryptodome for keccak256 (the same digest the EVM uses, NOT
the NIST SHA-3 variant in hashlib).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

try:
    from Crypto.Hash import keccak  # type: ignore
except ImportError:
    sys.exit("error: pycryptodome required. Install with: pip install pycryptodome")


# ─────────────────────────────────────────────────────────────────────────────
# ABI encoding helpers
# ─────────────────────────────────────────────────────────────────────────────

def _addr_to_32(addr_hex: str) -> bytes:
    addr_clean = addr_hex.lower().removeprefix("0x")
    if len(addr_clean) != 40:
        raise ValueError(f"address must be 20 bytes / 40 hex chars: {addr_hex!r}")
    return b"\x00" * 12 + bytes.fromhex(addr_clean)


def abi_encode_leaf(
    chain_id: int, attester_addr: str, beneficiary: str, amount: int, epoch: int
) -> bytes:
    """Mirror Solidity's abi.encode(uint256, address, address, uint128, uint64).

    The first two fields are the domain separator the contract uses to bind
    each leaf to its specific Attester instance on its specific chain. In ABI
    v2 each scalar < 32 bytes is left-padded to 32 bytes -> 5 * 32 = 160 bytes
    total.
    """
    out = chain_id.to_bytes(32, "big")                  # uint256 (full slot)
    out += _addr_to_32(attester_addr)                   # address (right-aligned)
    out += _addr_to_32(beneficiary)                     # address (right-aligned)
    out += amount.to_bytes(32, "big")                   # uint128 (right-aligned)
    out += epoch.to_bytes(32, "big")                    # uint64  (right-aligned)
    return out


def keccak256(data: bytes) -> bytes:
    h = keccak.new(digest_bits=256)
    h.update(data)
    return h.digest()


def leaf_hash(
    chain_id: int, attester_addr: str, beneficiary: str, amount: int, epoch: int
) -> bytes:
    return keccak256(
        abi_encode_leaf(chain_id, attester_addr, beneficiary, amount, epoch)
    )


def hash_pair(a: bytes, b: bytes) -> bytes:
    """Commutative pair hash — sort first, then concatenate, then keccak."""
    return keccak256(a + b) if a < b else keccak256(b + a)


# ─────────────────────────────────────────────────────────────────────────────
# Tree construction
# ─────────────────────────────────────────────────────────────────────────────

def build_tree(leaves: list[bytes]) -> tuple[bytes, list[list[bytes]]]:
    """Return (root, [proof per leaf]).

    For each leaf, the proof is the list of sibling hashes from leaf to root.
    With sorted-pair hashing the proof can be replayed in either order.
    """
    if not leaves:
        raise ValueError("empty leaf set")
    if len(leaves) == 1:
        return leaves[0], [[]]

    # Pad to a power of two by duplicating the last leaf (a common convention;
    # the contract's MerkleProof verifier tolerates this because pairs are sorted).
    padded = list(leaves)
    while (len(padded) & (len(padded) - 1)) != 0:
        padded.append(padded[-1])

    # Build level-by-level, tracking the index path for each ORIGINAL leaf.
    proofs: list[list[bytes]] = [[] for _ in leaves]
    level = padded[:]
    indices = list(range(len(leaves)))
    next_indices = list(range(len(padded)))

    while len(level) > 1:
        new_level: list[bytes] = []
        for i in range(0, len(level), 2):
            left, right = level[i], level[i + 1]
            new_level.append(hash_pair(left, right))
            # For each ORIGINAL leaf whose path runs through this pair, record sibling.
            for orig_idx, cur_idx in zip(indices, next_indices):
                if cur_idx == i:
                    proofs[orig_idx].append(right)
                elif cur_idx == i + 1:
                    proofs[orig_idx].append(left)
        next_indices = [cur // 2 for cur in next_indices]
        level = new_level

    return level[0], proofs


# ─────────────────────────────────────────────────────────────────────────────
# Sample batch
# ─────────────────────────────────────────────────────────────────────────────

EPOCH = 1
LEAVES_INPUT = [
    # Three synthetic beneficiaries each claiming a different kWh count for epoch 1.
    # Addresses are Anvil's default accounts so the on-chain step (06_claim) can
    # mint to a wallet that holds private keys locally.
    {"beneficiary": "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", "amount_wei": 100 * 10**18},  # alice
    {"beneficiary": "0x70997970C51812dc3A010C7d01b50e0d17dc79C8", "amount_wei": 200 * 10**18},  # bob
    {"beneficiary": "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC", "amount_wei": 150 * 10**18},  # carol
]


def main() -> int:
    import os
    # The contract binds each leaf to its (chainid, attester) domain separator
    # so a Merkle tree built for one Attester cannot be replayed against another.
    # The on-chain step (04_propose_batch) must supply these via env vars.
    chain_id = int(os.environ.get("CHAIN_ID", "31337"))
    attester_addr = os.environ.get("ATTESTER")
    if not attester_addr:
        print("error: ATTESTER env var required (the deployed NoethrionAttester address).", file=sys.stderr)
        print("       Run contracts/script/Deploy.s.sol first and export ATTESTER=0x...", file=sys.stderr)
        return 2

    leaves = [
        leaf_hash(chain_id, attester_addr, x["beneficiary"], x["amount_wei"], EPOCH)
        for x in LEAVES_INPUT
    ]
    root, proofs = build_tree(leaves)
    total_wei = sum(x["amount_wei"] for x in LEAVES_INPUT)

    out = {
        "epoch": EPOCH,
        "totalKwh": total_wei,            # 18-decimal NOET ≈ kWh in same scale for this demo
        "root": "0x" + root.hex(),
        "leaves": [
            {
                "beneficiary": x["beneficiary"],
                "amount_wei": x["amount_wei"],
                "leaf": "0x" + leaves[i].hex(),
                "proof": ["0x" + p.hex() for p in proofs[i]],
            }
            for i, x in enumerate(LEAVES_INPUT)
        ],
    }

    out_path = Path(__file__).resolve().parent / "batch.json"
    with out_path.open("w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=2)
    print(f"[03] wrote {out_path}")
    print(f"[03] root = {out['root']}")
    print(f"[03] {len(leaves)} leaves, total = {total_wei // 10**18} NOET (×10^18 wei)")
    print()
    print("Next step: 04_propose_batch.s.sol")
    return 0


if __name__ == "__main__":
    sys.exit(main())
