#!/bin/bash -eu

# Submit one test job to Testflinger from your machine, using the same job file and
# agent scripts as the "Test snap" GitHub workflow.
#
# Configure the test with the environment variables below, then run this script.
# Required: JOB_QUEUE, SNAP_NAME, SNAP_CHANNEL. See the README for all variables.
# Example:
#   JOB_QUEUE=maas-systemtests-amd64 SNAP_NAME=smollm2 SNAP_CHANNEL=latest/edge \
#   SELECT_ENGINE=cpu ./run.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOB_DIR="$SCRIPT_DIR/testflinger-jobs"
JOB_FILE="$JOB_DIR/test-snap.yaml"
TEMP_JOB_FILE="$JOB_DIR/test-snap.temp.yaml"

# Required
export JOB_QUEUE="${JOB_QUEUE:?Set JOB_QUEUE to the Testflinger queue}"
export SNAP_NAME="${SNAP_NAME:?Set SNAP_NAME to the snap to test}"
export SNAP_CHANNEL="${SNAP_CHANNEL:?Set SNAP_CHANNEL to the store channel to install from}"

# Optional. Defaults match the workflow inputs, except TEST_CHAT_TPS, which defaults to
# true so a plain run performs a test, and PROVISION_DATA (see below).
export DEVMODE="${DEVMODE:-false}"
export INSTALL_NVIDIA_DRIVER_VERSION="${INSTALL_NVIDIA_DRIVER_VERSION:-}"
export INSTALL_INTEL_NPU_DRIVER="${INSTALL_INTEL_NPU_DRIVER:-false}"
export SNAP_CONNECTIONS="${SNAP_CONNECTIONS:-}"
export EXPECTED_ENGINE="${EXPECTED_ENGINE:-}"
export SELECT_ENGINE="${SELECT_ENGINE:-}"
export TEST_CHAT_TPS="${TEST_CHAT_TPS:-true}"
export EXPECTED_TPS="${EXPECTED_TPS:-0}"
export TEST_IMAGE_PROMPT="${TEST_IMAGE_PROMPT:-false}"

# Provision data as one line of YAML or JSON. Defaults to Ubuntu 24.04.
# Set to an empty string to submit the job without provisioning.
export PROVISION_DATA="${PROVISION_DATA-distro: noble}"

if [ -n "$PROVISION_DATA" ] && ! command -v yq >/dev/null; then
  echo "yq is needed to add PROVISION_DATA to the job. Install it with 'sudo snap install yq'," >&2
  echo "or set PROVISION_DATA= to submit without provisioning." >&2
  exit 1
fi

# Substitute only the job's own variables
envsubst '$JOB_QUEUE $SNAP_NAME $SNAP_CHANNEL $DEVMODE $INSTALL_NVIDIA_DRIVER_VERSION
  $INSTALL_INTEL_NPU_DRIVER $SNAP_CONNECTIONS $EXPECTED_ENGINE $SELECT_ENGINE
  $TEST_CHAT_TPS $EXPECTED_TPS $TEST_IMAGE_PROMPT' \
  < "$JOB_FILE" > "$TEMP_JOB_FILE"

if [ -n "$PROVISION_DATA" ]; then
  yq eval '
  .provision_data = (strenv(PROVISION_DATA) | from_yaml) |
  .provision_data style=""
  ' -i "$TEMP_JOB_FILE"
fi

cat "$TEMP_JOB_FILE"

cd "$JOB_DIR"
testflinger submit --poll "$TEMP_JOB_FILE"
