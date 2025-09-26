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

test_endpoint() {
  local endpoint="$1"
  local description="$2"
  echo "Testing $description: $endpoint"

  if curl -s --fail-with-body --connect-timeout "$TIMEOUT" "$endpoint" >/dev/null; then
    echo "✓ $description: OK"
  else
    exit_error "✗ $description: Failed (HTTP >= 400 or connection error)"
  fi
}

use_engine_with_retry() {
  local engine="$1"
  local max_retries="${2:-3}"
  local retry_delay="${3:-30}"
  local attempt=1

  echo "Switching to engine: $engine"

  while [[ $attempt -le $max_retries ]]; do
    echo "Attempt $attempt/$max_retries: Switching to engine $engine"

    # Temporarily disable 'set -e' to handle command failure ourselves
    set +e
    local output
    local exit_code
    output=$("$AI_SNAP_NAME" use-engine "$engine" --assume-yes 2>&1)
    exit_code=$?
    # Re-enable 'set -e'
    set -e

    if [[ $exit_code -eq 0 ]]; then
      echo "✓ Successfully switched to engine: $engine"
      return 0
    fi

    # Check if the error contains "timed out"
    if [[ "$output" =~ "timed out" ]]; then
      echo "Engine switch timed out (attempt $attempt/$max_retries)"
      echo "Error output: $output" >&2

      if [[ $attempt -lt $max_retries ]]; then
        echo "Waiting ${retry_delay}s before retry..."
        sleep "$retry_delay"
        ((attempt++))
        continue
      else
        echo "Max retries reached. Engine switch failed due to timeout." >&2
        echo "$output" >&2
        return 1
      fi
    else
      # Non-timeout error, fail immediately
      echo "Engine switch failed with non-timeout error:" >&2
      echo "$output" >&2
      return 1
    fi
  done
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

SERVER_PORT=$($AI_SNAP_NAME get http.port)

# Base URL for API
BASE_URL="http://localhost:$SERVER_PORT"
TIMEOUT=5

# Check if port is listening
if ss -tuln | grep -q ":$SERVER_PORT "; then
  echo "Port $SERVER_PORT is listening"
else
  exit_error "Port $SERVER_PORT is not listening. Is the snap running?"
fi

# Check health endpoint
test_endpoint "$BASE_URL/health" "Health check"

# Check models endpoint
test_endpoint "$BASE_URL/v1/models" "List available models"

chat_payload='{
        "model": "default",
        "messages": [{"role": "user", "content": "Hello"}],
        "max_tokens": 5
}'

if curl -s --fail-with-body \
  --connect-timeout "$TIMEOUT" \
  -X POST \
  -H "Content-Type: application/json" \
  -d "$chat_payload" \
  "$BASE_URL/v1/chat/completions" >/dev/null; then
  echo "✓ Chat completion: OK"
else
  exit_error "Chat completion failed (may indicate service issues)"
fi

echo "Running tests against snap: $AI_SNAP_NAME"
echo "Selected engine: $MODEL_ENGINE"

echo "Check installation..."
snap list "$AI_SNAP_NAME"

echo "Check all configs"
snap get "$AI_SNAP_NAME" -d

echo "Check all configs"
"$AI_SNAP_NAME" get

echo "Get a config subset"
$AI_SNAP_NAME get http

echo "Get specific config"
$AI_SNAP_NAME get http.port

echo "Chek current engine status"
$AI_SNAP_NAME status

echo "Chek current engine"
$AI_SNAP_NAME show-engine

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

mapfile -t avail_engines < <($AI_SNAP_NAME list-engines | tail -n +2 | awk '{print $1}' | sort)
echo -e "Available engines:\n${avail_engines[*]}"

mapfile -t src_engines < <(find "$SCRIPT_DIR/../engines" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort)
echo -e "Declared engines:\n${src_engines[*]}"

if [[ ${#avail_engines[@]} -ne ${#src_engines[@]} ]]; then
  exit_error "Size of available engines does not match declared engines."
fi

# The items in both arrays should perfectly match since they are sorted
if [[ "${avail_engines[*]}" != "${src_engines[*]}" ]]; then
  exit_error "Available engines do not match declared engines."
fi

echo "Query all engines..."
for i in "${src_engines[@]}"; do
  $AI_SNAP_NAME show-engine "$i"
done

# Test: Switch engine with retry logic
echo "Testing engine switch..."
if ! use_engine_with_retry "$MODEL_ENGINE"; then
  exit_error "Failed to switch to engine: $MODEL_ENGINE"
fi

echo "Check on status if engine switched correctly..."
curr_engine=$("$AI_SNAP_NAME" status | head -n 1 | cut -d ' ' -f 2)

if [[ "$curr_engine" != "$MODEL_ENGINE" ]]; then
  exit_error "Current engine from status command ($curr_engine) does not match expected engine ($MODEL_ENGINE)."
fi

echo "Restart the snap to apply the config change"
snap stop "$AI_SNAP_NAME"
snap start "$AI_SNAP_NAME"

echo "Check on configs if engine switched correctly..."
get_engine=$(snap get -l $AI_SNAP_NAME cache | awk '/^cache.active-engine[[:space:]]/ {print $2}')
if [[ "$get_engine" != "$MODEL_ENGINE" ]]; then
  exit_error "Engine value from config ($get_engine) does not match expected engine ($MODEL_ENGINE)."
fi
