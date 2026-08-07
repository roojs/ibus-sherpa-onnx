#!/usr/bin/env bash
# CLI twin of Preferences model install: cache → pkexec → user model symlink.
# Prefer ibus-setup-sherpa-onnx for interactive use.
#
# Usage (as your normal user — not sudo for the whole script):
#   ./scripts/cli-fetch-nemotron-model.sh           # 560ms (default)
#   ./scripts/cli-fetch-nemotron-model.sh 1120      # higher accuracy, more latency
#
# Optional: ROOJS_TAG=vX.Y.Z to prefer github.com/roojs/sherpa-onnx/releases
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
  echo "Run as your user (not root). Install uses pkexec for the system move." >&2
  exit 2
fi

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
SYSTEM_DIR="/usr/share/ibus-sherpa-onnx/models/$DIR_NAME"
USER_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/ibus-sherpa-onnx"
MODEL_LINK="$USER_CONFIG/model"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/ibus-sherpa-onnx/download"

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

echo "Fetching GitHub release digest for $ARCHIVE ..."
EXPECT_HASH=$(curl -fsSL \
  -H 'Accept: application/vnd.github+json' \
  -H 'User-Agent: ibus-sherpa-onnx' \
  'https://api.github.com/repos/k2-fsa/sherpa-onnx/releases/tags/asr-models' \
  | python3 -c "
import json, sys
want = sys.argv[1]
for a in json.load(sys.stdin).get('assets', []):
    if a.get('name') != want:
        continue
    d = a.get('digest') or ''
    if not d.startswith('sha256:'):
        sys.exit('digest missing or not sha256 for ' + want)
    print(d[len('sha256:'):])
    sys.exit(0)
sys.exit('asset not found: ' + want)
" "$ARCHIVE")
if [ -z "$EXPECT_HASH" ]; then
  echo "Empty digest from GitHub API for $ARCHIVE" >&2
  exit 1
fi

HELPER="/usr/libexec/ibus-sherpa-onnx-install-model"
if [ ! -x "$HELPER" ]; then
  HELPER="$SCRIPT_DIR/install-model.sh"
fi

model_ok() {
  local d="$1"
  [ -f "$d/encoder.int8.onnx" ] && [ -f "$d/tokens.txt" ] || return 1
  [ -f "$d/.sha256" ] || return 1
  local got
  got=$(tr -d '[:space:]' <"$d/.sha256")
  [ "$got" = "$EXPECT_HASH" ]
}

link_user() {
  mkdir -p "$USER_CONFIG"
  ln -sfn "$SYSTEM_DIR" "$MODEL_LINK"
  echo "Done: $MODEL_LINK -> $SYSTEM_DIR"
  echo "Restart the IME if it was already running (ibus restart)."
}

if model_ok "$SYSTEM_DIR"; then
  echo "Model already installed: $SYSTEM_DIR"
  link_user
  exit 0
fi

if [ -n "${ROOJS_TAG:-}" ]; then
  PRIMARY_URL="https://github.com/roojs/sherpa-onnx/releases/download/${ROOJS_TAG}/${ARCHIVE}"
else
  PRIMARY_URL="https://github.com/roojs/sherpa-onnx/releases/download/asr-models/${ARCHIVE}"
fi
FALLBACK_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/${ARCHIVE}"

mkdir -p "$CACHE"
cd "$CACHE"

verify_archive() {
  echo "Verifying SHA-256 of $ARCHIVE ..."
  echo "$EXPECT_HASH  $ARCHIVE" | sha256sum -c -
}

if model_ok "$DIR_NAME"; then
  echo "Staged model already verified: $CACHE/$DIR_NAME"
else
  if [ -e "$DIR_NAME" ]; then
    echo "Removing incomplete staged tree: $DIR_NAME"
    rm -rf "$DIR_NAME"
  fi
  if [ -f "$ARCHIVE" ]; then
    if ! verify_archive; then
      echo "Checksum mismatch; removing $ARCHIVE"
      rm -f "$ARCHIVE"
    fi
  fi
  if [ ! -f "$ARCHIVE" ]; then
    echo "Downloading Nemotron ${CHUNK}ms ..."
    if ! wget -c "$PRIMARY_URL" -O "$ARCHIVE"; then
      echo "roojs URL failed; trying upstream k2-fsa ..."
      rm -f "$ARCHIVE"
      wget -c "$FALLBACK_URL" -O "$ARCHIVE"
    fi
    verify_archive
  fi

  echo "Unpacking $ARCHIVE ..."
  tar --no-same-owner -xf "$ARCHIVE"
  if [ ! -f "$DIR_NAME/encoder.int8.onnx" ] || [ ! -f "$DIR_NAME/tokens.txt" ]; then
    echo "Unpack missing encoder/tokens; removing" >&2
    rm -rf "$DIR_NAME"
    exit 1
  fi
  printf '%s\n' "$EXPECT_HASH" >"$DIR_NAME/.sha256"
fi

echo "Installing into system models (pkexec) ..."
if [ -x /usr/libexec/ibus-sherpa-onnx-install-model ]; then
  pkexec /usr/libexec/ibus-sherpa-onnx-install-model "$DIR_NAME"
else
  # Checkout / unpackaged: policy only covers libexec; use sudo + PKEXEC_UID.
  sudo env PKEXEC_UID="$(id -u)" "$HELPER" "$DIR_NAME"
fi

if ! model_ok "$SYSTEM_DIR"; then
  echo "System install missing or incomplete: $SYSTEM_DIR" >&2
  exit 1
fi
link_user
