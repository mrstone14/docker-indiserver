#!/bin/sh
set -eu

# Entrypoint wrapper: start indiserver in background, then start indi-web (foreground)
# If INDI_DRIVERS is set, this is informational only — drivers should be built into the image.

echo "Entry point: starting indiserver + indi-web"

if command -v indiserver >/dev/null 2>&1; then
  echo "Starting indiserver with FIFO /tmp/indiserver.fifo on port ${INDI_PORT:-7624}..."
  # Ensure fifo exists
  FIFO=/tmp/indiserver.fifo
  rm -f "$FIFO" 2>/dev/null || true
  mkfifo "$FIFO" || true
  # Start indiserver in fifo mode so it remains running and accepts dynamic driver commands
  indiserver -f "$FIFO" -p "${INDI_PORT:-7624}" &
  INDI_PID=$!
  echo "indiserver PID=${INDI_PID}"
else
  echo "Warning: indiserver not found in PATH"
  INDI_PID=""
fi

# Forward signals to child processes
_term() {
  echo "Entrypoint: received SIGTERM, stopping children..."
  [ -n "${INDI_PID}" ] && kill "${INDI_PID}" 2>/dev/null || true
  [ -n "${WEB_PID:-}" ] && kill "${WEB_PID}" 2>/dev/null || true
  exit 0
}

trap _term INT TERM

# Start indi-web in foreground (with provided args)
echo "Starting indi-web with args: $@"
indi-web "$@" &
WEB_PID=$!

# Wait for indi-web to exit; then shut down indiserver if running
wait $WEB_PID

echo "indi-web exited; stopping indiserver if running"
[ -n "${INDI_PID}" ] && kill "${INDI_PID}" 2>/dev/null || true
wait || true

exit 0
