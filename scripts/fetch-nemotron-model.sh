#!/usr/bin/env bash
# Fetch and unpack a Nemotron streaming ASR model into the engine's model tree.
#
# Destination is chosen by euid (no MODELS_DIR / env path knobs):
#   root  → /usr/share/ibus-sherpa-onnx/models/<dir>  + model → that tree
#   user  → ~/.config/ibus-sherpa-onnx/models/<dir>   + model → that tree
#
# Usage:
#   ./scripts/fetch-nemotron-model.sh           # 560ms (default)
#   ./scripts/fetch-nemotron-model.sh 1120      # higher accuracy, more latency
#   sudo ./scripts/fetch-nemotron-model.sh      # system-wide install
#   ./scripts/fetch-nemotron-model.sh 160
#   ./scripts/fetch-nemotron-model.sh 80
#
# Optional: ROOJS_TAG=vX.Y.Z to prefer github.com/roojs/sherpa-onnx/releases
set -euo pipefail

CHUNK="${1:-560}"
case "$CHUNK" in
  80|160|560|1120) ;;
  *)
    echo "Usage: $0 [80|160|560|1120]" >&2
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

if [ -n "${ROOJS_TAG:-}" ]; then
  PRIMARY_URL="https://github.com/roojs/sherpa-onnx/releases/download/${ROOJS_TAG}/${ARCHIVE}"
else
  PRIMARY_URL="https://github.com/roojs/sherpa-onnx/releases/download/asr-models/${ARCHIVE}"
fi
FALLBACK_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/${ARCHIVE}"

mkdir -p "$MODELS_DIR"
cd "$MODELS_DIR"

if [ -f "$DIR_NAME/encoder.int8.onnx" ] && [ -f "$DIR_NAME/tokens.txt" ]; then
  echo "Model already unpacked: $MODELS_DIR/$DIR_NAME"
else
  if [ ! -f "$ARCHIVE" ]; then
    echo "Downloading $ARCHIVE …"
    if ! wget -c "$PRIMARY_URL" -O "$ARCHIVE"; then
      echo "roojs URL failed; trying upstream k2-fsa …"
      rm -f "$ARCHIVE"
      wget -c "$FALLBACK_URL" -O "$ARCHIVE"
    fi
  fi

  echo "Unpacking $ARCHIVE …"
  tar --no-same-owner -xvf "$ARCHIVE"
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
