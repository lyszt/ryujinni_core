#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
  echo "❌ This script must be run with bash. Try: bash run.sh" >&2
  exit 1
fi

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$PROJECT_DIR/vendor/bin"
STREAMLINK_BIN="$PROJECT_DIR/vendor/streamlink-venv/bin"
LEGACY_BIN="$PROJECT_DIR/vendor/ffmpeg/bin"

export PATH="$BIN_DIR:$STREAMLINK_BIN:$PATH"
if [[ -d "$LEGACY_BIN" ]]; then
  export PATH="$LEGACY_BIN:$PATH"
fi

missing=0
for tool in ffmpeg ffprobe youtube-dl streamlink; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "⚠️  Missing dependency '$tool'. Run ./install.sh first." >&2
    missing=1
  fi
done

if [[ $missing -eq 1 ]]; then
  exit 1
fi

mix deps.get
mix ecto.create
mix ecto.migrate
mix compile

NODE_NAME="${NODE_NAME:-ryujin_dev}"
ERLANG_COOKIE="${ERLANG_COOKIE:-ryujin_cookie}"

iex --sname "$NODE_NAME" --cookie "$ERLANG_COOKIE" -S mix phx.server
