#!/usr/bin/env bash
# Fetch and unpack a Nemotron streaming ASR model into models/.
#
# Usage:
#   ./scripts/fetch-nemotron-model.sh           # 560ms (default)
#   ./scripts/fetch-nemotron-model.sh 1120      # higher accuracy, more latency
#   ./scripts/fetch-nemotron-model.sh 160
#   ./scripts/fetch-nemotron-model.sh 80
#
# Optional: ROOJS_TAG=vX.Y.Z to prefer github.com/roojs/sherpa-onnx/releases
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODELS_DIR="${MODELS_DIR:-$ROOT/models}"

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
  echo "Run: ./build/stt-poc $MODELS_DIR/$DIR_NAME"
  exit 0
fi

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

echo "Done: $MODELS_DIR/$DIR_NAME"
ls -lh "$DIR_NAME"
echo
echo "Run: ./build/stt-poc models/$DIR_NAME"
echo "With stats: ./build/stt-poc --stats models/$DIR_NAME"
