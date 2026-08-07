#!/usr/bin/env bash
# Interim fetch helper until in-app Soup download (Phase D). Prefer Preferences;
# do not expand this script further.
#
# Destination is chosen by euid (no MODELS_DIR / env path knobs):
#   root  → /usr/share/ibus-sherpa-onnx/models/<dir>  + model → that tree
#   user  → ~/.config/ibus-sherpa-onnx/models/<dir>   + model → that tree
#
# Archive SHA-256 is verified against data/checksums/<dir>.sha256 (installed under
# /usr/share/ibus-sherpa-onnx/checksums/). A matching .sha256 stamp is written
# into the model tree only after verify + unpack; without that stamp the model
# is treated as incomplete.
#
# Usage:
#   ./scripts/fetch-nemotron-model.sh           # 560ms (default)
#   ./scripts/fetch-nemotron-model.sh 1120      # higher accuracy, more latency
#   sudo ./scripts/fetch-nemotron-model.sh      # system-wide install
#
# Optional: ROOJS_TAG=vX.Y.Z to prefer github.com/roojs/sherpa-onnx/releases
set -euo pipefail

CHUNK="${1:-560}"
case "$CHUNK" in
  560|1120) ;;
  *)
    echo "Usage: $0 [560|1120]" >&2
    exit 2
    ;;
esac

ARCHIVE="sherpa-onnx-nemotron-speech-streaming-en-0.6b-${CHUNK}ms-int8-2026-04-25.tar.bz2"
DIR_NAME="${ARCHIVE%.tar.bz2}"

if [ "$(id -u)" -eq 0 ]; then
  PREFIX="/usr/share/ibus-sherpa-onnx"
else
  PREFIX="${XDG_CONFIG_HOME:-$HOME/.config}/ibus-sherpa-onnx"
fi

MODELS_DIR="$PREFIX/models"
MODEL_LINK="$PREFIX/model"

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SUMS_DIR="/usr/share/ibus-sherpa-onnx/checksums"
if [ ! -d "$SUMS_DIR" ]; then
  SUMS_DIR="$SCRIPT_DIR/../data/checksums"
fi
EXPECTED_SUM="$SUMS_DIR/${DIR_NAME}.sha256"
if [ ! -f "$EXPECTED_SUM" ]; then
  echo "No checksum file for $DIR_NAME (looked in $SUMS_DIR)" >&2
  exit 1
fi
EXPECT_HASH=$(awk '{print $1; exit}' "$EXPECTED_SUM")
if [ -z "$EXPECT_HASH" ]; then
  echo "Empty checksum file: $EXPECTED_SUM" >&2
  exit 1
fi

if [ -n "${ROOJS_TAG:-}" ]; then
  PRIMARY_URL="https://github.com/roojs/sherpa-onnx/releases/download/${ROOJS_TAG}/${ARCHIVE}"
else
  PRIMARY_URL="https://github.com/roojs/sherpa-onnx/releases/download/asr-models/${ARCHIVE}"
fi
FALLBACK_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/${ARCHIVE}"

mkdir -p "$MODELS_DIR"
cd "$MODELS_DIR"

model_ok() {
  local d="$1"
  [ -f "$d/encoder.int8.onnx" ] && [ -f "$d/tokens.txt" ] || return 1
  [ -f "$d/.sha256" ] || return 1
  local got
  got=$(tr -d '[:space:]' <"$d/.sha256")
  [ "$got" = "$EXPECT_HASH" ]
}

verify_archive() {
  echo "Verifying SHA-256 of $ARCHIVE …"
  echo "$EXPECT_HASH  $ARCHIVE" | sha256sum -c -
}

if model_ok "$DIR_NAME"; then
  echo "Model already verified: $MODELS_DIR/$DIR_NAME"
else
  if [ -e "$DIR_NAME" ]; then
    echo "Removing incomplete model tree: $DIR_NAME"
    rm -rf "$DIR_NAME"
  fi
  if [ -f "$ARCHIVE" ]; then
    if ! verify_archive; then
      echo "Checksum mismatch; removing $ARCHIVE"
      rm -f "$ARCHIVE"
    fi
  fi
  if [ ! -f "$ARCHIVE" ]; then
    echo "Downloading $ARCHIVE …"
    if ! wget -c "$PRIMARY_URL" -O "$ARCHIVE"; then
      echo "roojs URL failed; trying upstream k2-fsa …"
      rm -f "$ARCHIVE"
      wget -c "$FALLBACK_URL" -O "$ARCHIVE"
    fi
    verify_archive
  fi

  echo "Unpacking $ARCHIVE …"
  tar --no-same-owner -xvf "$ARCHIVE"
  if [ ! -f "$DIR_NAME/encoder.int8.onnx" ] || [ ! -f "$DIR_NAME/tokens.txt" ]; then
    echo "Unpack missing encoder/tokens; removing" >&2
    rm -rf "$DIR_NAME"
    exit 1
  fi
  printf '%s\n' "$EXPECT_HASH" >"$DIR_NAME/.sha256"
fi

ln -sfn "$MODELS_DIR/$DIR_NAME" "$MODEL_LINK"
echo "Done: $MODEL_LINK -> $MODELS_DIR/$DIR_NAME"
ls -lh "$DIR_NAME" | head
echo
if [ "$(id -u)" -eq 0 ]; then
  echo "System model ready. Restart the IME if it was already running (ibus restart)."
else
  echo "User model ready. Restart the IME if it was already running (ibus restart)."
fi
