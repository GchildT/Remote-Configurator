#!/usr/bin/env bash
set -euo pipefail

SOURCE="/c/Drone/Music/Tame Impala - Cause I'm A Man.flac"
OUT_DIR="public/audio"
OUT_FILE="$OUT_DIR/hook-track.mp3"

mkdir -p "$OUT_DIR"

ffmpeg -y -ss 00:01:11 -t 00:00:30 -i "$SOURCE" -c:a libmp3lame -q:a 2 "$OUT_FILE"

echo "Wrote $OUT_FILE"
