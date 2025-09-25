#!/bin/bash

set -Eeuo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exit_error() {
  echo "Error: ${1}" >&2
  exit 1
}

usage() {
  echo "Usage: $0 <ai-model-snap-name> <engine>"
  echo "Runs smoke tests for one specified engine against a local AI model snap."
  exit 1
}

# Check for root privileges
if ((EUID != 0)); then
  echo "This script must be run as root or with sudo."
  exit 1
fi

# Check if snap name and engine are provided
if [ $# -lt 2 ]; then
  echo "Error: engine and snap name are required."
  usage
fi
AI_SNAP_NAME=$1
MODEL_ENGINE=$2

echo "Running tests against snap: $AI_SNAP_NAME"
echo "Selected engine: $MODEL_ENGINE"

echo "Check installation..."
snap list "$AI_SNAP_NAME"

echo "Check all configs"
snap get "$AI_SNAP_NAME" -d

echo "Get a config subset"
$AI_SNAP_NAME get http

echo "Get specific config"
$AI_SNAP_NAME get http.port

echo "Chek current engine status"
$AI_SNAP_NAME status

echo "Change the config"
$AI_SNAP_NAME set http.port=9999

echo "Restart the snap to apply the config change"
snap stop "$AI_SNAP_NAME"
snap start "$AI_SNAP_NAME"

port=$($AI_SNAP_NAME get http.port)
if (("$port" != 9999)); then
  exit_error "Config change did not persist."
fi

echo "Check engines"

mapfile -t avail_engines < <(qwen-vl list-engines --all | tail -n +2 | awk '{print $1}' | sort)
echo -e "Available engines:\n${avail_engines[*]}"

mapfile -t src_engines < <(find "$SCRIPT_DIR/../engines" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort)
echo -e "Declared engines:\n${src_engines[*]}"

if [[ ${#avail_engines[@]} -ne ${#src_engines[@]} ]]; then
  exit_error "Size of available engines does not match declared engines."
fi

# The itens in both arrays should perfectly match since they are sorted
if [[ "${avail_engines[*]}" != "${src_engines[*]}" ]]; then
  exit_error "Available engines do not match declared engines."
fi

echo "Query all engines..."
for i in "${src_engines[@]}"; do
  $AI_SNAP_NAME show-engine "$i"
done

echo "Switch engine to $MODEL_ENGINE"
$AI_SNAP_NAME use-engine "$MODEL_ENGINE" --assume-yes

echo "Check on status if engine switched correctly..."
curr_engine=$("$AI_SNAP_NAME" status | head -n 1 | cut -d ' ' -f 2)

if [[ "$curr_engine" != "$MODEL_ENGINE" ]]; then
  exit_error "Current engine from status command ($curr_engine) does not match expected engine ($MODEL_ENGINE)."
fi

echo "Restart the snap to apply the config change"
snap stop "$AI_SNAP_NAME"
snap start "$AI_SNAP_NAME"

echo "Check on configs if engine switched correctly..."
get_engine=$(snap get -l qwen-vl | awk '/^engine[[:space:]]/ {print $2}')
if [[ "$get_engine" != "$MODEL_ENGINE" ]]; then
  exit_error "Engine value from config ($get_engine) does not match expected engine ($MODEL_ENGINE)."
fi
