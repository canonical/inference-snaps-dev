#!/bin/bash -eu

# Select an engine if the configuration is set, otherwise do auto selection
if [[ -n "${SELECT_ENGINE}" ]]; then
  # Set expected engine to the selected one
  EXPECTED_ENGINE=$SELECT_ENGINE
else
  SELECT_ENGINE="--auto"
fi

echo "::group::Selecting engine"
# Engine might install multiple large components and can run for a long time
# without producing any output. Run in the background and print elapsed time
# periodically so the CI runner does not consider the job stalled.
# Retry if use-engine exits with a non-zero exit code.
max_retries=3
poll_interval=30
engine_selected=0

for attempt in $(seq 1 $max_retries); do
  echo "Running \"$SNAP_NAME use-engine\" (attempt $attempt/$max_retries)"

  _run sudo "$SNAP_NAME" use-engine "$SELECT_ENGINE" --assume-yes &
  use_engine_pid=$!

  # Background poller: print elapsed time periodically to avoid CI timeout.
  (
    elapsed=0
    while kill -0 "$use_engine_pid" 2>/dev/null; do
      sleep "$poll_interval"
      elapsed=$(( elapsed + poll_interval ))
      echo "⏳ still running: ${elapsed}s"
    done
  ) &
  poller_pid=$!

  # Wait and capture use-engine's exit code. Done in an if to avoid exiting the script on non-zero.
  if wait "$use_engine_pid"; then
    exit_code=0
  else
    exit_code=$?
  fi

  # Stop the poller if still running
  kill "$poller_pid" || true
  wait "$poller_pid" || true

  if [ "$exit_code" -eq 0 ]; then
    echo "✔ Selecting engine succeeded"
    engine_selected=1
    break
  fi

  echo "✘ Selecting engine failed with exit code $exit_code (attempt $attempt/$max_retries)"
  # On older snaps the download of components times out. Wait for snapd to finish before retrying.
  wait-for-snap-changes
done

if [ $engine_selected -eq 0 ]; then
  echo "Get logs"
  _run sudo journalctl -a | grep "$SNAP_NAME"
  echo "::error::Machine: $dut_hostname, failed selecting engine after $max_retries tries"
  echo "::endgroup::"
  exit 1
fi


# Restart server after changing engine
echo "Restarting snap"
_run sudo snap restart "$SNAP_NAME"
wait-for-snap-changes

echo "::endgroup::"

echo "::group::Checking selected engine"
selected_engine=$(_run "$SNAP_NAME" status --format=json | jq -r .engine)
echo "Selected engine: $selected_engine"

if [[ -n "${EXPECTED_ENGINE}" ]]; then
  if [ "$EXPECTED_ENGINE" != "$selected_engine" ]; then
    echo "::error::Machine: $dut_hostname, incorrect engine selected: $selected_engine"
    echo "::endgroup::"
    exit 1
  fi
fi
echo "::endgroup::"
