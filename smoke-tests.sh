#!/bin/bash

# Instrucions:
#
# This script runs smokes tests for a model snap installed from store.
# It might not work for a local installation unless that all needed components installed.

set -Eeuo pipefail

# =============================================================================
# CONFIGURATION AND GLOBALS
# =============================================================================

# Configuration defaults
TIMEOUT=5
DEFAULT_MAX_RETRIES=3
DEFAULT_RETRY_DELAY=30

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_section() {
  echo -e "\n${BLUE}=== $1 ===${NC}"
}

exit_error() {
  log_error "$1"
  exit 1
}

usage() {
  echo "Usage: $0 <ai-model-snap-name> <engine>"
  echo "Runs smoke tests for one specified engine against a local AI model snap."
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

check_root_privileges() {
  if ((EUID != 0)); then
    exit_error "This script must be run as root or with sudo."
  fi
}

validate_arguments() {
  if [ $# -lt 2 ]; then
    usage
    exit_error "Engine and snap name are required."
  fi
}

check_port_listening() {
  local port="$1"

  if ss -tuln | grep -q ":$port "; then
    log_info "Port $port is listening"
  else
    exit_error "Port $port is not listening. Is the snap running?"
  fi
}

# =============================================================================
# HTTP API TESTING FUNCTIONS
# =============================================================================

test_endpoint() {
  local endpoint="$1"
  local description="$2"

  log_info "Testing $description: $endpoint"

  if curl -s --fail-with-body --connect-timeout "$TIMEOUT" "$endpoint" >/dev/null; then
    log_info "✓ $description: OK"
  else
    exit_error "✗ $description: Failed (HTTP >= 400 or connection error)"
  fi
}

test_chat_completion() {
  local base_url="$1"

  log_info "Testing chat completion endpoint..."

  local chat_payload='{
        "model": "default",
        "messages": [{"role": "user", "content": "Hello"}],
        "max_tokens": 5
    }'

  if curl -s --fail-with-body \
    --connect-timeout "$TIMEOUT" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "$chat_payload" \
    "$base_url/chat/completions" >/dev/null; then
    log_info "✓ Chat completion: OK"
  else
    exit_error "Chat completion failed (may indicate service issues)"
  fi
}

run_api_tests() {
  local base_url="$1"
  local base_path="$2"

  log_section "API Endpoint Tests"

  # Test models endpoint
  test_endpoint "$base_url/$base_path/models" "List available models"

  # Test chat completion
  test_chat_completion "$base_url"
}

# =============================================================================
# SNAP MANAGEMENT FUNCTIONS
# =============================================================================

test_snap_installation() {
  local snap_name="$1"

  log_section "Snap Installation Test"
  log_info "Checking snap installation..."
  snap list "$snap_name"
}

test_configuration_management() {
  local snap_name="$1"

  log_section "Configuration Management Tests"

  log_info "Checking all configs (snap get)..."
  snap get "$snap_name" -d

  log_info "Checking all configs (snap command)..."
  "$snap_name" get

  log_info "Getting config subset..."
  "$snap_name" get http

  log_info "Getting specific config..."
  "$snap_name" get http.port

  log_info "Testing configuration change..."
  "$snap_name" set http.port=9999

  # Verify config change persisted
  local port
  port=$("$snap_name" get http.port)
  if (("$port" != 9999)); then
    exit_error "Config change did not persist."
  fi
  log_info "✓ Configuration change persisted successfully"
}

# =============================================================================
# ENGINE MANAGEMENT FUNCTIONS
# =============================================================================

test_engine_listing() {
  local snap_name="$1"

  log_section "Engine Listing Tests"

  log_info "Comparing available vs declared engines..."

  mapfile -t avail_engines < <("$snap_name" list-engines | tail -n +2 | awk '{print $1}' | sort)
  echo -e "Available engines:\n${avail_engines[*]}"

  mapfile -t src_engines < <(find "/snap/$AI_SNAP_NAME/current/engines/" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort)
  echo -e "Declared engines:\n${src_engines[*]}"

  if [[ ${#avail_engines[@]} -ne ${#src_engines[@]} ]]; then
    exit_error "Number of engines reported by CLI does not match number of engine directories."
  fi

  # The items in both arrays should perfectly match since they are sorted
  if [[ "${avail_engines[*]}" != "${src_engines[*]}" ]]; then
    exit_error "Available engines do not match declared engines."
  fi

  log_info "✓ Engine lists match successfully"

  log_info "Querying individual engines..."
  for engine in "${src_engines[@]}"; do
    log_info "Querying engine: $engine"
    "$snap_name" show-engine "$engine"
  done
}

use_engine_with_retry() {
  local snap_name="$1"
  local engine="$2"
  local max_retries="${3:-$DEFAULT_MAX_RETRIES}"
  local retry_delay="${4:-$DEFAULT_RETRY_DELAY}"
  local attempt=1

  log_info "Switching to engine: $engine"

  while [[ $attempt -le $max_retries ]]; do
    log_info "Attempt $attempt/$max_retries: Switching to engine $engine"

    # Temporarily disable 'set -e' to handle command failure ourselves
    set +e
    local output
    local exit_code
    output=$("$snap_name" use-engine "$engine" --assume-yes 2>&1)
    exit_code=$?
    # Re-enable 'set -e'
    set -e

    if [[ $exit_code -eq 0 ]]; then
      log_info "✓ Successfully switched to engine: $engine"
      return 0
    fi

    # Check if the error contains "timed out" or "change in progress"
    if [[ "$output" =~ "timed out" || "$output" =~ "change in progress" ]]; then
      log_warning "Engine switch timed out (attempt $attempt/$max_retries)"
      echo "Error output: $output" >&2

      if [[ $attempt -lt $max_retries ]]; then
        log_info "Waiting ${retry_delay}s before retry..."
        sleep "$retry_delay"
        ((attempt++))
        continue
      else
        log_error "Max retries reached. Engine switch failed due to timeout."
        echo "$output" >&2
        return 1
      fi
    else
      # Non-timeout error, fail immediately
      log_error "Engine switch failed with non-timeout error:"
      echo "$output" >&2
      return 1
    fi
    sleep 2
  done
}

test_engine_switching() {
  local snap_name="$1"
  local target_engine="$2"

  log_section "Engine Switching Tests"

  log_info "Checking current engine status..."
  "$snap_name" status

  log_info "Showing current engine..."
  "$snap_name" show-engine

  # Test engine switch with retry logic
  log_info "Testing engine switch with retry logic..."
  if ! use_engine_with_retry "$snap_name" "$target_engine"; then
    exit_error "Failed to switch to engine: $target_engine"
  fi

  # Verify engine switch via status command
  log_info "Verifying engine switch via status command..."
  local curr_engine
  curr_engine=$("$snap_name" status | head -n 1 | cut -d ' ' -f 2)

  if [[ "$curr_engine" != "$target_engine" ]]; then
    exit_error "Current engine from status command ($curr_engine) does not match expected engine ($target_engine)."
  fi
  log_info "✓ Engine switch verified via status command"
  # Verify engine persisted in config
  log_info "Verifying engine persisted in configuration..."
  local config_engine
  config_engine=$(snap get -l "$snap_name" cache | awk '/^cache.active-engine[[:space:]]/ {print $2}')
  if [[ "$config_engine" != "$target_engine" ]]; then
    exit_error "Engine value from config ($config_engine) does not match expected engine ($target_engine)."
  fi
  log_info "✓ Engine switch persisted successfully in configuration"
}

# =============================================================================
# MAIN EXECUTION FUNCTION
# =============================================================================

main() {
  local snap_name="$1"
  local target_engine="$2"

  log_section "Starting Smoke Tests"
  log_info "Running tests against snap: $snap_name"
  log_info "Selected engine: $target_engine"

  # Get server settings
  local server_port
  server_port=$("$snap_name" get http.port)
  local base_path
  base_path=$("$snap_name" get http.base-path)
  local base_url="http://localhost:$server_port"

  # Pre-flight checks
  check_port_listening "$server_port"

  # Run all test suites
  run_api_tests "$base_url" "$base_path"
  test_snap_installation "$snap_name"
  test_configuration_management "$snap_name"
  test_engine_listing "$snap_name"
  test_engine_switching "$snap_name" "$target_engine"

  log_section "All Smoke Tests Completed Successfully!"
}

# =============================================================================
# SCRIPT ENTRY POINT
# =============================================================================

# Validation
check_root_privileges
validate_arguments "$@"

# Extract arguments
AI_SNAP_NAME="$1"
MODEL_ENGINE="$2"

# Run main function
main "$AI_SNAP_NAME" "$MODEL_ENGINE"
