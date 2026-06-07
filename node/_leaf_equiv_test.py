#!/usr/bin/env python3
"""Equivalence check: the verifier node must compute the on-chain leaf hash
identically to tools/verify_attestation.py compute-leaf (the source of truth that
matches NoethrionAttester.claim()). Run with the node venv. Exit 0 if identical."""
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "node"))
from verifier_node import compute_leaf  # noqa: E402

# Public test vector (Anvil chain id + the deterministic genesis addresses).
chain_id = 31337
attester = "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512"
beneficiary = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
amount = 100 * 10**18
epoch = 1

cli = subprocess.run(
    [sys.executable, str(REPO / "tools" / "verify_attestation.py"), "compute-leaf",
     "--chain-id", str(chain_id), "--attester", attester,
     "--beneficiary", beneficiary, "--amount", str(amount), "--epoch", str(epoch)],
    capture_output=True, text=True,
)
m = re.search(r"0x[a-fA-F0-9]{64}", cli.stdout + cli.stderr)
cli_leaf = m.group(0).lower() if m else None
node_leaf = compute_leaf(chain_id, attester, beneficiary, amount, epoch).lower()

print("CLI :", cli_leaf)
print("NODE:", node_leaf)
if cli_leaf and cli_leaf == node_leaf:
    print("RESULT: IDENTICAL — node computes leaves exactly like the contract/CLI")
    sys.exit(0)
print("RESULT: MISMATCH")
sys.exit(1)
