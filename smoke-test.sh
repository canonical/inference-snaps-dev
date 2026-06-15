#!/bin/bash

# Instrucions:
#
# This script runs smokes tests for a model snap installed from store.
# It might not work for a local installation unless that all needed components are installed.

set -Eeuo pipefail

# =============================================================================
# ERROR HANDLING
# =============================================================================

error_handler() {
  local exit_code=$?
  local line_no=$1
  local bash_lineno=$2
  local last_command="$3"
  local func_name="${4:-main}"

  log_error "Script failed with exit code $exit_code"
  log_error "Error occurred in function: $func_name"
  log_error "Failed command: $last_command"
  log_error "Line number: $line_no"
  log_error "Bash line number: $bash_lineno"

  # Print call stack
  log_error "Call stack:"
  local frame=0
  while caller $frame >/dev/null 2>&1; do
    local caller_info
    caller_info=$(caller $frame)
    log_error "  [$frame] $caller_info"
    ((frame++))
  done

  exit "$exit_code"
}

# Set up trap for ERR signal
# ${LINENO} - line number where error occurred
# ${BASH_LINENO[0]} - line number in the calling function
# ${BASH_COMMAND} - command that caused the error
# ${FUNCNAME[1]} - name of the function where error occurred
trap 'error_handler ${LINENO} ${BASH_LINENO[0]} "$BASH_COMMAND" "${FUNCNAME[1]}"' ERR

# =============================================================================
# CONFIGURATION AND GLOBALS
# =============================================================================

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
  echo "Usage: $0 <inference-snap-name> <engine>"
  echo "Runs smoke tests for one specified engine against an inference snap."
  echo
  echo "Example:"
  echo "./$(basename "$0") deepseek-r1 cpu-tiny"
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

check_root_privileges() {
  if ((EUID != 0)); then
    exit_error "This script must be run as root or with sudo."
  fi
}

check_for_curl() {
  if ! command -v curl &>/dev/null; then
    exit_error "curl is not installed. Please install curl to continue."
  fi
}

check_for_jq() {
  if ! command -v jq &>/dev/null; then
    exit_error "jq is not available. Please install it and try again."
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
  local timeout_seconds=300
  local retry_delay=10
  local start_time
  start_time=$(date +%s)

  while true; do
    local current_time
    current_time=$(date +%s)
    local elapsed=$((current_time - start_time))

    log_info "Checking whether port $port is listening (${elapsed}/${timeout_seconds}s)"

    if ss -tuln | grep -q ":$port "; then
      log_info "✓ Port $port is listening"
      return 0
    fi

    if [[ $elapsed -lt $timeout_seconds ]]; then
      log_warning "Port $port not listening; retrying in ${retry_delay}s"
      sleep "$retry_delay"
    else
      exit_error "✗ Time out after ${timeout_seconds}s waiting for port $port to listen."
    fi
  done
}

# =============================================================================
# HTTP API TESTING FUNCTIONS
# =============================================================================

test_endpoint_models() {
  local base_url="$1"
  local timeout_seconds=300  # 5 minutes
  local retry_delay=10
  local connection_timeout=60
  local start_time
  start_time=$(date +%s)

  local endpoint="$base_url/models"

  log_info "Testing OpenAI models endpoint."

  while true; do
    local current_time
    current_time=$(date +%s)
    local elapsed=$((current_time - start_time))

    log_info "Checking $endpoint ($elapsed/${timeout_seconds}s)"

    if curl --retry 0 --fail-with-body --write-out '\n' --connect-timeout $connection_timeout "$endpoint"; then
      log_info "✓ $endpoint: Pass"
      return 0
    fi

    current_time=$(date +%s)
    elapsed=$((current_time - start_time))

    if [[ $elapsed -lt $timeout_seconds ]]; then
      log_warning "Endpoint failed; retrying in ${retry_delay}s"
      sleep "$retry_delay"
    else
      exit_error "✗ $endpoint: Fails after $timeout_seconds seconds"
    fi
  done
}

test_endpoint_chat_completion() {
  local base_url="$1"
  local model_name="$2"
  local max_retries=5
  local retry_delay=60
  local connection_timeout=60
  local attempt=1
  local endpoint="$base_url/chat/completions"

  log_info "Testing OpenAI chat completions endpoints."

  local system_message="You are a helpful assistant."
  local prompt="Hello!"
  local json_body
  json_body=$(
    cat <<EOF
{
  "model": "$model_name",
  "messages": [
    {
      "role": "user",
      "content": "$prompt"
    }
  ],
  "temperature": 0,
  "max_tokens": 5
}
EOF
  )

  local compact_json_body
  compact_json_body=$(echo "$json_body" | jq -c .)

  local api_response
  while [[ $attempt -le $max_retries ]]; do
    log_info "Checking $endpoint ($attempt/$max_retries)"

    set +e
    set -x # log the curl command for debugging
    api_response=$(
      curl -X POST "$endpoint" \
        -H "Content-Type: application/json" \
        -d "$compact_json_body" \
        --connect-timeout $connection_timeout \
        --max-time 600 \
        --retry 0 \
        --fail-with-body \
        --write-out '\n' \
        2>/dev/null
    )
    set +x
    local curl_exit_code=$?
    set -e

    if [[ $curl_exit_code -eq 0 ]]; then
      if [[ -z "$api_response" ]]; then
        exit_error "Empty response from server"
      fi

      log_info "✓ $endpoint: Pass"
      return 0
    fi

    if [[ $attempt -lt $max_retries ]]; then
      log_warning "Chat completion failed; retrying in ${retry_delay}s"
      sleep "$retry_delay"
    fi

    ((attempt++))
  done

  exit_error "✗ $endpoint: Fail after $max_retries attempts"

}

run_api_tests() {
  local base_url="$1"
  local model_name="$2"

  log_section "API Endpoint Tests"

  test_endpoint_models "$base_url"
  test_endpoint_chat_completion "$base_url" "$model_name"
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
  local default_port

  log_section "Configuration Management Tests"

  log_info "Checking all configs (snap get $snap_name)..."
  snap get "$snap_name" -d

  log_info "Checking all configs ($snap_name get)..."
  "$snap_name" get

  log_info "Getting specific config..."
  default_port=$("$snap_name" get http.port)
  echo "$default_port"

  log_info "Testing configuration change..."
  "$snap_name" set http.port=9999 --assume-yes

  # Verify config change persisted
  local port
  port=$("$snap_name" get http.port)
  if (("$port" != 9999)); then
    exit_error "Config change did not persist."
  fi
  log_info "✓ Configuration change persisted successfully"

  log_info "Reverting configuration change..."
  "$snap_name" set http.port="$default_port" --assume-yes
}

# =============================================================================
# ENGINE MANAGEMENT FUNCTIONS
# =============================================================================

test_engine_listing() {
  local snap_name="$1"

  log_section "Engine Listing Tests"

  log_info "Comparing available vs declared engines..."

  mapfile -t avail_engines < <("$snap_name" list-engines --format=json | jq -r '.engines[].name' | sort)
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
    "$snap_name" show-engine "$engine" >/dev/null
  done
}

get_curr_engine() {
  local snap_name="$1"
  "$snap_name" status --format=json | jq -r '.engine'
}

test_engine_switching() {
  local snap_name="$1"
  local target_engine="$2"

  log_section "Engine Switching Tests"

  log_info "Checking status..."
  "$snap_name" status

  log_info "Showing current engine..."
  "$snap_name" show-engine

  log_info "Testing engine switch..."
  if ! "$snap_name" use-engine "$target_engine" --assume-yes; then
    exit_error "Failed to switch to engine: $target_engine"
  fi

  log_info "Verifying engine switch via status command..."
  local curr_engine
  curr_engine=$(get_curr_engine "$snap_name")
  if [[ "$curr_engine" != "$target_engine" ]]; then
    exit_error "Current engine from status command ($curr_engine) does not match expected engine ($target_engine)."
  fi
  log_info "✓ Engine switch verified via status command"
}

test_automatic_engine_selection() {
  local snap_name="$1"
  log_section "Automatic Engine Selection Test"

  log_info "Running: $snap_name use-engine --auto"
  engine=$("$snap_name" use-engine --auto --assume-yes | grep -oP 'Selected engine: \K\S+')

  log_info "Selected engine: $engine"

  snap stop "$snap_name"
  snap start "$snap_name"

  check=$(get_curr_engine "$snap_name")

  if [[ "$check" != "$engine" ]]; then
    exit_error "Automatic engine selection failed: status shows $check but expected $engine"
  fi
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
  local base_url=$("$snap_name" status --format=json | jq -r '.endpoints.openai' )
  local model_name
  model_name=$("$snap_name" status --format=json | jq -r '.model.name')

  # Pre-flight checks
  check_port_listening "$server_port"

  # Run all test suites
  test_snap_installation "$snap_name"
  test_configuration_management "$snap_name"
  test_engine_listing "$snap_name"
  test_automatic_engine_selection "$snap_name"
  test_engine_switching "$snap_name" "$target_engine"
  run_api_tests "$base_url" "$model_name"

  log_section "All Smoke Tests Completed Successfully!"
}

# =============================================================================
# SCRIPT ENTRY POINT
# =============================================================================

# Validation
check_root_privileges
check_for_curl
check_for_jq
validate_arguments "$@"

# Extract arguments
AI_SNAP_NAME="$1"
MODEL_ENGINE="$2"

# Run main function
main "$AI_SNAP_NAME" "$MODEL_ENGINE"
