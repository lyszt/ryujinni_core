#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
  echo "❌ This script must be run with bash. Try: bash install.sh" >&2
  exit 1
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

echo "🔧 Starting installation for Ryujin..."

VENDOR_ROOT="$SCRIPT_DIR/vendor"
BIN_DIR="$VENDOR_ROOT/bin"
CACHE_DIR="$VENDOR_ROOT/cache"
STREAMLINK_VENV="$VENDOR_ROOT/streamlink-venv"

mkdir -p "$BIN_DIR" "$CACHE_DIR"

LEGACY_BIN_DIR="$VENDOR_ROOT/ffmpeg/bin"
if [[ -d "$LEGACY_BIN_DIR" ]]; then
  echo "♻️  Migrating legacy vendor/ffmpeg layout..."
  for exec in ffmpeg ffprobe youtube-dl; do
    if [[ -x "$LEGACY_BIN_DIR/$exec" && ! -x "$BIN_DIR/$exec" ]]; then
      cp "$LEGACY_BIN_DIR/$exec" "$BIN_DIR/"
      chmod +x "$BIN_DIR/$exec"
    fi
  done
fi

# ────────────────────────────────────────────────
# 1. Prepare Elixir project
# ────────────────────────────────────────────────
if [[ "${SKIP_MIX:-0}" != "1" ]]; then
  echo "📦 Syncing Mix dependencies..."
  mix deps.get
  mix compile
else
  echo "⏭️  SKIP_MIX=1 set; skipping Mix dependency sync."
fi

# ────────────────────────────────────────────────
# 2. Download and stage FFmpeg locally
# ────────────────────────────────────────────────
echo "🎞️  Ensuring FFmpeg is available locally..."
FFMPEG_URL="https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz"
ARCHIVE_PATH="$CACHE_DIR/ffmpeg.tar.xz"

if [[ ! -x "$BIN_DIR/ffmpeg" || ! -x "$BIN_DIR/ffprobe" ]]; then
  echo "⬇️  Downloading FFmpeg archive..."
  curl -sSL "$FFMPEG_URL" -o "$ARCHIVE_PATH"

  TMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t ffmpeg)"
  tar -xf "$ARCHIVE_PATH" -C "$TMP_DIR" --strip-components=1

  cp "$TMP_DIR/ffmpeg" "$BIN_DIR/"
  cp "$TMP_DIR/ffprobe" "$BIN_DIR/"
  chmod +x "$BIN_DIR/ffmpeg" "$BIN_DIR/ffprobe"

  rm -rf "$TMP_DIR" "$ARCHIVE_PATH"
  echo "✅ FFmpeg binaries staged in $BIN_DIR."
else
  echo "✅ FFmpeg already present at $BIN_DIR; skipping download."
fi

"$BIN_DIR/ffmpeg" -version | head -n 1

# ────────────────────────────────────────────────
# 3. Install media helpers (Streamlink + yt-dlp)
# ────────────────────────────────────────────────
echo "🌊  Ensuring Python media virtualenv is ready..."
if ! command -v python3 >/dev/null 2>&1; then
  echo "❌ python3 is required to set up Streamlink. Install python3 and rerun."
  exit 1
fi

if [[ ! -x "$STREAMLINK_VENV/bin/python" ]]; then
  python3 -m venv "$STREAMLINK_VENV"
fi

"$STREAMLINK_VENV/bin/pip" install --upgrade pip >/dev/null
"$STREAMLINK_VENV/bin/pip" install --upgrade streamlink yt-dlp >/dev/null

STREAMLINK_BIN_PATH="$STREAMLINK_VENV/bin/streamlink"
YT_DLP_BIN_PATH="$STREAMLINK_VENV/bin/yt-dlp"
YTDL_SHIM="$BIN_DIR/youtube-dl"

ln -sf "$YT_DLP_BIN_PATH" "$YTDL_SHIM"
chmod +x "$YTDL_SHIM"

"$STREAMLINK_BIN_PATH" --version | head -n 1
"$YT_DLP_BIN_PATH" --version | head -n 1

echo "✅ Streamlink installed in $STREAMLINK_VENV."
echo "✅ yt-dlp linked at $YTDL_SHIM."


cat <<INSTRUCTIONS
🎉 Installation complete!
INSTRUCTIONS
