#!/usr/bin/env sh
# Noethrion verifier — one-line installer.
#
#   curl -fsSL https://raw.githubusercontent.com/noethrion/noethrion/main/node/install.sh | sh
#
# Installs the single-binary independent verifier for your platform, fetches the
# published genesis attestation data, and verifies it LIVE against the public
# chain — on your machine, no server in the trust path. Don't trust us; the
# binary reads the chain and re-derives every leaf itself.
set -eu

REPO="noethrion/noethrion"
TAG="node-v0.1.1"
RPC="https://ethereum-sepolia-rpc.publicnode.com"
CHAIN_ID="11155111"
BATCH_URL="https://noethrion.com/network/batch.json"
DEST="${NOETHRION_HOME:-$HOME/.noethrion}"
BIN="$DEST/noethrion-verify"

green() { printf '\033[0;32m%s\033[0m\n' "$1"; }
red()   { printf '\033[0;31m%s\033[0m\n' "$1"; }
info()  { printf '  %s\n' "$1"; }

# sha256 <file> — portable digest (sha256sum on Linux, shasum on macOS).
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'
  fi
}

printf '\n  \033[0;32mη\033[0m  Noethrion verifier — installer\n\n'

# ── detect platform ──────────────────────────────────────────────────────────
os="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m)"
case "$arch" in
  x86_64|amd64)  arch="amd64" ;;
  arm64|aarch64) arch="arm64" ;;
esac
case "$os" in
  linux|darwin) : ;;
  *) echo "  Unsupported shell OS: $os. Windows users: grab the .exe from"
     echo "  https://github.com/$REPO/releases/tag/$TAG"; exit 1 ;;
esac
info "platform: $os/$arch"

mkdir -p "$DEST/published"

# ── get the binary: prebuilt release asset, else build from source ───────────
asset="noethrion-verify-${os}-${arch}"
url="https://github.com/$REPO/releases/download/$TAG/$asset"
info "downloading verifier ($asset)..."
if curl -fsSL "$url" -o "$BIN" 2>/dev/null && [ -s "$BIN" ]; then
  # Integrity check: if the release publishes SHA256SUMS, the downloaded
  # binary's digest must match its entry — a mismatch aborts the install.
  sums_url="https://github.com/$REPO/releases/download/$TAG/SHA256SUMS"
  sums_file="$DEST/SHA256SUMS"
  if curl -fsSL "$sums_url" -o "$sums_file" 2>/dev/null && [ -s "$sums_file" ]; then
    expected="$(awk -v a="$asset" '$2 == a {print $1}' "$sums_file")"
    if [ -z "$expected" ]; then
      info "warning: $asset not listed in SHA256SUMS, skipping integrity check"
    else
      actual="$(sha256 "$BIN")"
      if [ "$actual" != "$expected" ]; then
        red "  checksum mismatch for $asset"
        info "expected: $expected"
        info "got:      $actual"
        rm -f "$BIN"
        exit 1
      fi
      green "  checksum verified ($asset)"
    fi
  else
    info "warning: checksum file not found in release, skipping integrity check"
  fi
  chmod +x "$BIN"
  green "  installed: $BIN"
else
  info "no prebuilt binary for $os/$arch — building from source (needs Go + git)..."
  command -v go  >/dev/null 2>&1 || { echo "  Go not found — install from https://go.dev/dl/ and re-run."; exit 1; }
  command -v git >/dev/null 2>&1 || { echo "  git not found."; exit 1; }
  tmp="$(mktemp -d)"
  git clone --depth 1 "https://github.com/$REPO" "$tmp/src" >/dev/null 2>&1
  ( cd "$tmp/src/node/go" && go build -o "$BIN" . )
  chmod +x "$BIN"
  rm -rf "$tmp"
  green "  built: $BIN"
fi

# ── fetch the published genesis attestation data ─────────────────────────────
info "fetching genesis attestation data..."
curl -fsSL "$BATCH_URL" -o "$DEST/published/batch-1.json"

# ── verify the genesis live, on YOUR machine ─────────────────────────────────
printf '\n  verifying the genesis attestation against the live chain...\n\n'
rc=0
"$BIN" --rpc "$RPC" \
       --attester 0x02De07a2CF1E757D8D53de217B5dA372E84114cC \
       --chain-id "$CHAIN_ID" \
       --data-dir "$DEST/published" --once --start-epoch 1 || rc=$?

printf '\n'
if [ "$rc" -eq 0 ]; then
  green "  verified — the on-chain commitment and the published data reconcile"
else
  red "  verification FAILED (exit $rc) — see the verifier output above"
  exit "$rc"
fi

cat <<EOF

  Done. Binary: $BIN

  Verify again any time:
    "$BIN" --rpc $RPC \\
      --attester 0x02De07a2CF1E757D8D53de217B5dA372E84114cC \\
      --chain-id $CHAIN_ID --data-dir "$DEST/published" --once

  Run it as a continuous watchdog (drop --once):
    "$BIN" --rpc $RPC \\
      --attester 0x02De07a2CF1E757D8D53de217B5dA372E84114cC \\
      --chain-id $CHAIN_ID --data-dir "$DEST/published"

  That binary read the chain and re-derived every leaf itself — no trust required.
  η = useful energy / total energy.
EOF
