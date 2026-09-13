#!/usr/bin/env bash
set -euo pipefail

# Windows-style path (not /c/... Git-Bash style, unlike the sibling Short
# project's script) -- this machine's ffmpeg is a native Windows build that
# does not resolve /c/... paths; confirmed by direct reproduction.
SOURCE="C:\\Drone\\Music\\Tame Impala - Cause I'm A Man.flac"
OUT_DIR="public/audio"
OUT_FILE="$OUT_DIR/hook-track.mp3"

mkdir -p "$OUT_DIR"

ffmpeg -y -ss 00:01:11 -t 00:00:45 -i "$SOURCE" -c:a libmp3lame -q:a 2 "$OUT_FILE"

echo "Wrote $OUT_FILE"
