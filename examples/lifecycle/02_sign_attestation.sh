#!/usr/bin/env bash
# 02 · Sign a sample attestation tuple
#
# Produces examples/lifecycle/attestation.json — a single signed measurement
# that the subsequent lifecycle steps treat as one leaf of a larger batch.
#
# Run after 01_generate_key.md (requires attester.key in this directory).

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
KEY="$HERE/attester.key"
OUT="$HERE/attestation.json"

if [[ ! -f "$KEY" ]]; then
  echo "error: $KEY not found. Run step 01 first." >&2
  exit 2
fi

# Sample inputs — fixed for reproducibility in the example. In production these
# come from the kWh meter (wh, timestamp) and the secure element (device serial).
DEVICE_ID="0123456789ABCDEF12"   # 9-byte hex; ATECC608B serial format
TIMESTAMP=1747094400              # Unix seconds (2025-05-13 00:00:00 UTC)
WH=1473                           # 1.473 kWh produced in this interval

echo "[02] signing tuple device_id=$DEVICE_ID timestamp=$TIMESTAMP wh=$WH"
python3 "$REPO/tools/provision_atecc.py" sign-test \
    --key "$KEY" \
    --device-id "$DEVICE_ID" \
    --timestamp "$TIMESTAMP" \
    --wh "$WH" \
    > "$OUT"

echo "[02] wrote $OUT"
echo ""
echo "Inspect with:  jq . $OUT"
echo "Next step:     03_build_merkle_tree.py"
