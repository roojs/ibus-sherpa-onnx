#!/usr/bin/env bash
# Polkit helper: move a staged Nemotron tree into the system models store.
# No network. Does not touch ~/.config/…/model.
#
# Usage (via pkexec):
#   pkexec /usr/libexec/ibus-sherpa-onnx-install-model <dir-name>
set -euo pipefail

NAME="${1:-}"
case "$NAME" in
  sherpa-onnx-nemotron-speech-streaming-en-0.6b-560ms-int8-2026-04-25|\
  sherpa-onnx-nemotron-speech-streaming-en-0.6b-1120ms-int8-2026-04-25) ;;
  *)
    echo "Usage: $0 <nemotron-dir-name>" >&2
    exit 2
    ;;
esac
if [[ "$NAME" == *"/"* ]] || [[ "$NAME" == "."* ]]; then
  echo "Invalid model name" >&2
  exit 2
fi

UID_NUM="${PKEXEC_UID:-}"
if [[ -z "$UID_NUM" ]]; then
  echo "PKEXEC_UID missing (run via pkexec)" >&2
  exit 2
fi
USER_HOME=$(getent passwd "$UID_NUM" | cut -d: -f6)
if [[ -z "$USER_HOME" || ! -d "$USER_HOME" ]]; then
  echo "Cannot resolve home for uid $UID_NUM" >&2
  exit 1
fi

CACHE="$USER_HOME/.cache/ibus-sherpa-onnx/download"
SRC="$CACHE/$NAME"
DEST_ROOT="/usr/share/ibus-sherpa-onnx/models"
DEST="$DEST_ROOT/$NAME"

# Staging must live under that user's download cache.
case "$SRC" in
  "$CACHE"/*) ;;
  *)
    echo "Refusing path outside cache" >&2
    exit 1
    ;;
esac
if [[ ! -d "$SRC" ]]; then
  echo "Missing staged model: $SRC" >&2
  exit 1
fi
if [[ ! -f "$SRC/encoder.int8.onnx" || ! -f "$SRC/tokens.txt" ]]; then
  echo "Staged tree incomplete: $SRC" >&2
  exit 1
fi

mkdir -p "$DEST_ROOT"
if [[ -d "$DEST" ]]; then
  # Already installed — drop staging / archive only.
  rm -rf "$SRC"
  rm -f "$CACHE/$NAME.tar.bz2" "$CACHE/$NAME.tar.bz2.partial"
  exit 0
fi

mv "$SRC" "$DEST"
rm -f "$CACHE/$NAME.tar.bz2" "$CACHE/$NAME.tar.bz2.partial"
exit 0
