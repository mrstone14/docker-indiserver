#!/bin/sh

set -eu


echo "Entry point: starting indiserver + indi-web"

if ! command -v indiserver >/dev/null 2>&1; then
  echo "Error: indiserver not found in PATH. Exiting."
  exit 1
fi

# Require INDI_DRIVERS to be set and non-empty
if [ -z "${INDI_DRIVERS:-}" ]; then
  echo "Error: INDI_DRIVERS environment variable must be set and non-empty. Exiting."
  exit 1
fi


# Map build driver names to executable names if needed
DRIVER_ARGS=""
for drv in $INDI_DRIVERS; do
  # Map 'indi-libcamera' to 'indi_libcamera' for runtime
  if [ "$drv" = "indi-libcamera" ]; then
    exe_name="indi_libcamera"
  else
    exe_name="$drv"
  fi
  # Resolve driver executable path order:
  # 1) absolute path provided as-is
  # 2) /usr/bin/<exe_name>
  # 3) /usr/bin/indi_<exe_name>
  if [ -x "$exe_name" ]; then
    DRIVER_ARGS="$DRIVER_ARGS $exe_name"
  elif [ -x "/usr/bin/$exe_name" ]; then
    DRIVER_ARGS="$DRIVER_ARGS /usr/bin/$exe_name"
  elif [ -x "/usr/bin/indi_$exe_name" ]; then
    DRIVER_ARGS="$DRIVER_ARGS /usr/bin/indi_$exe_name"
  else
    DRIVER_ARGS="$DRIVER_ARGS $exe_name"
  fi
done

echo "Starting indiserver on port ${INDI_PORT:-7624} with drivers: $DRIVER_ARGS"
indiserver -p "${INDI_PORT:-7624}" $DRIVER_ARGS &
INDI_PID=$!
echo "indiserver PID=${INDI_PID}"


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
