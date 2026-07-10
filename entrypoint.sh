#!/bin/sh
# Maps environment variables to bambucam's positional arguments and selects
# which compiled binary to run, then execs it as PID 1.
set -eu

BIN_DIR="${BAMBUCAM_BIN_DIR:-/usr/local/bin}"

SERVER_RAW="${SERVER:-HTTP}"
SERVER_UP=$(printf '%s' "$SERVER_RAW" | tr '[:lower:]' '[:upper:]')
case "$SERVER_UP" in
  HTTP) base="bambucam-http" ;;
  RTP)  base="bambucam-rtp" ;;
  *)
    echo "bambucam: invalid SERVER='$SERVER_RAW' (expected HTTP or RTP)" >&2
    exit 2
    ;;
esac

PORT="${BAMBU_PORT:-8080}"

if [ -n "${BAMBU_FAKE:-}" ]; then
  bin="${base}-fake"
  ip="fake"; device="fake"; passcode="fake"
else
  bin="$base"
  missing=""
  [ -z "${BAMBU_IP:-}" ]       && missing="$missing BAMBU_IP"
  [ -z "${BAMBU_DEVICE:-}" ]   && missing="$missing BAMBU_DEVICE"
  [ -z "${BAMBU_PASSCODE:-}" ] && missing="$missing BAMBU_PASSCODE"
  if [ -n "$missing" ]; then
    echo "bambucam: missing required environment variable(s):$missing" >&2
    echo "bambucam: set them, or set BAMBU_FAKE=1 to run the test pattern." >&2
    exit 3
  fi
  ip="$BAMBU_IP"; device="$BAMBU_DEVICE"; passcode="$BAMBU_PASSCODE"
fi

exe="$BIN_DIR/$bin"
if [ ! -x "$exe" ]; then
  echo "bambucam: binary not found or not executable: $exe" >&2
  exit 4
fi

echo "bambucam: starting $bin on port $PORT (SERVER=$SERVER_UP)" >&2
exec "$exe" "$ip" "$device" "$passcode" "$PORT"
