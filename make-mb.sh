#!/usr/bin/env bash
# make-mb.sh — create an ~N MB file (text/zero/random)
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  make-mb.sh <SIZE_MB> [OUTPUT] [--mode text|zero|random]

Examples:
  make-mb.sh 50 big.txt              # ~50 MB of readable text (default)
  make-mb.sh 10 bin.zero --mode zero # ~10 MB of zeros
  make-mb.sh 5  bin.rand --mode random # ~5 MB of random data

Notes:
- SIZE_MB — integer number of megabytes (MiB: 1 MiB = 1,048,576 bytes).
- mode:
    text   — readable lorem ipsum text (good for HTTP / parsing tests).
    zero   — zero bytes (fastest).
    random — random bytes (slower, good for entropy tests).
EOF
}

# ---- Parse arguments
if [[ ${1:-} == "-h" || ${1:-} == "--help" || $# -lt 1 ]]; then
  usage; exit 0
fi

SIZE_MB="$1"; shift
[[ "$SIZE_MB" =~ ^[0-9]+$ ]] || { echo "ERROR: SIZE_MB must be an integer"; exit 1; }

OUT="${1:-}"; [[ -n "${1:-}" ]] && shift || OUT="sample_${SIZE_MB}MB"
MODE="text"
if [[ ${1:-} == "--mode" && -n ${2:-} ]]; then
  MODE="$2"; shift 2
fi
[[ "$MODE" =~ ^(text|zero|random)$ ]] || { echo "ERROR: --mode must be text|zero|random"; exit 1; }

BYTES=$(( SIZE_MB * 1024 * 1024 ))

echo "Creating ~${SIZE_MB} MiB -> ${OUT} (mode: ${MODE})"

# ---- Fast path for zero/random modes when system tools support it
if [[ "$MODE" == "zero" || "$MODE" == "random" ]]; then
  if command -v fallocate >/dev/null 2>&1 && [[ "$MODE" == "zero" ]]; then
    # Linux: allocate a file of exact size (may be sparse)
    fallocate -l "${BYTES}" "${OUT}"
    echo "Done (fallocate)."; exit 0
  fi

  if command -v mkfile >/dev/null 2>&1 && [[ "$MODE" == "zero" ]]; then
    # macOS / BSD: exact-size zero-filled file
    mkfile -n "${BYTES}" "${OUT}" 2>/dev/null || mkfile "${BYTES}" "${OUT}"
    echo "Done (mkfile)."; exit 0
  fi

  if command -v truncate >/dev/null 2>&1 && [[ "$MODE" == "zero" ]]; then
    # Generic POSIX truncate
    truncate -s "${BYTES}" "${OUT}"
    echo "Done (truncate)."; exit 0
  fi

  # Fallback: portable version using dd
  if [[ "$MODE" == "zero" ]]; then
    dd if=/dev/zero of="${OUT}" bs=1M count="${SIZE_MB}" status=progress conv=fsync
  else
    dd if=/dev/urandom of="${OUT}" bs=1M count="${SIZE_MB}" status=progress conv=fsync
  fi
  echo "Done (dd)."; exit 0
fi

# ---- text mode (portable, readable, approximately exact MiB)
# Generates human-readable text content.
# yes outputs endless repeated lines, head -c trims to the exact byte count.
# LC_ALL=C speeds up byte processing.
LC_ALL=C yes "Lorem ipsum dolor sit amet, consectetur adipiscing elit. 0123456789 ABCDEFGHIJKLMNOPQRSTUVWXYZ." \
  | head -c "${BYTES}" > "${OUT}"

# Ensure the file size is exact (pad or trim if needed)
actual=$(wc -c < "${OUT}")
if (( actual < BYTES )); then
  # Pad with zeros if smaller
  dd if=/dev/zero bs=1 count=0 seek="${BYTES}" oflag=seek_bytes of="${OUT}" 2>/dev/null || \
  truncate -s "${BYTES}" "${OUT}" 2>/dev/null || true
elif (( actual > BYTES )); then
  # Trim if larger
  truncate -s "${BYTES}" "${OUT}" 2>/dev/null || \
  dd if="${OUT}" of="${OUT}.tmp" bs=1 count="${BYTES}" status=none && mv "${OUT}.tmp" "${OUT}"
fi

echo "Done (text). Size: $(wc -c < "${OUT}") bytes"
