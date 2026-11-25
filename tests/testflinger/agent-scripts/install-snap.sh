#!/bin/bash -eu

echo "::group::Installing snap"

# Testflinger has a timeout checking for any output on stdout and stderr.
# The no-wait is to work around this, preventing the snap install step from causing a timeout on a slow internet
# connection. The no-wait, along with wait-for-snap-changes creates output to stdout, which prevents this timeout.

echo "Remove $SNAP_NAME if already installed"
_run sudo snap remove "$SNAP_NAME" --no-wait
wait-for-snap-changes

max_retries=3
snap_installed=0

for attempt in $(seq 1 $max_retries); do
  echo "Installing $SNAP_NAME from $SNAP_CHANNEL (attempt $attempt/$max_retries)"
  if [ "${DEVMODE:-false}" = true ]; then
    snap_install_cmd=(sudo snap install "$SNAP_NAME" --channel "$SNAP_CHANNEL" --devmode --no-wait)
  else
    snap_install_cmd=(sudo snap install "$SNAP_NAME" --channel "$SNAP_CHANNEL" --no-wait)
  fi
  _run "${snap_install_cmd[@]}"
  wait-for-snap-changes

  # Check if snap is installed by running it
  if _run "$SNAP_NAME" &> /dev/null; then
    echo "Snap $SNAP_NAME installed successfully"
    snap_installed=1
    break
  else
    echo "Snap $SNAP_NAME not found after installation attempt $attempt"
  fi
done

if [ $snap_installed -eq 0 ]; then
  echo "Get logs"
  _run sudo journalctl -a | grep "$SNAP_NAME"
  echo "::error::Machine: $dut_hostname, failed installing snap after $max_retries tries"
  echo "::endgroup::"
  exit 1
fi

echo "✔ Snap installed"
echo "::endgroup::"
