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

# If INDI_DRIVERS is set, send driver start commands into the indiserver FIFO
if [ -n "${INDI_DRIVERS:-}" ]; then
  echo "INDI_DRIVERS set: $INDI_DRIVERS — attempting to load drivers via FIFO $FIFO"
  # Give indiserver a moment to be ready to read the FIFO
  sleep 0.5
  for drv in $INDI_DRIVERS; do
    # Resolve driver executable path order:
    # 1) absolute path provided as-is
    # 2) /usr/bin/<drv>
    # 3) /usr/bin/indi_<drv>
    if [ -x "$drv" ]; then
      cmd="$drv"
    elif [ -x "/usr/bin/$drv" ]; then
      cmd="/usr/bin/$drv"
    elif [ -x "/usr/bin/indi_$drv" ]; then
      cmd="/usr/bin/indi_$drv"
    else
      # Fallback: write the raw token — indiserver may resolve it
      cmd="$drv"
    fi

    echo "-> Loading driver: $cmd"
    # Write command into FIFO for indiserver to process
    if [ -p "$FIFO" ]; then
      echo "$cmd" >"$FIFO" || true
    else
      echo "Warning: FIFO $FIFO not present; cannot load $cmd"
    fi
    # small delay between driver loads
    sleep 0.3
  done
fi

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
