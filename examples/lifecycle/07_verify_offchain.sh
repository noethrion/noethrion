#!/usr/bin/env bash
# 07 · Off-chain independent verification of the attestation.
#
# Demonstrates that the signed tuple from step 02 can be verified end-to-end
# WITHOUT any chain access — given only the device public key and the canonical
# payload. This is the path a relying party uses when it does not run an
# Ethereum light client.
#
# Run after step 02 (requires attestation.json + attester.key.pub).

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"

ATT="$HERE/attestation.json"
PUB="$HERE/attester.key.pub"

if [[ ! -f "$ATT" ]]; then
  echo "error: $ATT not found. Run step 02 first." >&2
  exit 2
fi
if [[ ! -f "$PUB" ]]; then
  echo "error: $PUB not found. Run step 01 first." >&2
  exit 2
fi

echo "[07] verifying ECDSA P-256 signature off-chain..."
python3 "$REPO/tools/verify_attestation.py" verify-signature \
    --attestation "$ATT" \
    --pubkey "$PUB"

echo ""
echo "[07] end-to-end lifecycle complete."
echo ""
echo "What this proved:"
echo "  - The attester held a P-256 keypair"
echo "  - The attester produced a signed (deviceId, ts, kWh) tuple"
echo "  - An anchored Merkle root committed to it"
echo "  - The batch finalized past the challenge window"
echo "  - A claim against the leaf minted NOET to the beneficiary"
echo "  - A verifier with only the public key + payload validates the signature"
