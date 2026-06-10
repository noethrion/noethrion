#!/usr/bin/env sh
# Generate SHA256SUMS for the verifier release binaries.
#
#   node/release_checksums.sh [dir-with-binaries]    # defaults to .
#
# Writes <dir>/SHA256SUMS in `sha256sum` format ("<hash>  <filename>"), one
# line per noethrion-verify-* release asset. Upload SHA256SUMS next to the
# binaries on the GitHub release: node/install.sh downloads it and refuses to
# install a binary whose digest does not match its entry.
set -eu

DIR="${1:-.}"
cd "$DIR"

assets=""
for f in noethrion-verify-*; do
  [ -f "$f" ] || continue
  case "$f" in
    *.sha256|SHA256SUMS) continue ;;
  esac
  assets="$assets $f"
done
if [ -z "$assets" ]; then
  echo "error: no noethrion-verify-* binaries found in $DIR" >&2
  exit 1
fi

# shellcheck disable=SC2086 — word-splitting of $assets is intentional.
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum $assets > SHA256SUMS
else
  shasum -a 256 $assets > SHA256SUMS
fi

echo "wrote $(pwd)/SHA256SUMS:"
cat SHA256SUMS
