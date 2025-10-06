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

# Configuration defaults (can be overridden by environment variables)
: "${CURL_TIMEOUT:=10}"
: "${DEFAULT_MAX_RETRIES:=3}"
: "${DEFAULT_RETRY_DELAY:=30}"

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
  echo
  echo "Environment variables (optional overrides):"
  echo "  CURL_TIMEOUT         Default: 10"
  echo "  DEFAULT_MAX_RETRIES  Default: 3"
  echo "  DEFAULT_RETRY_DELAY  Default: 30"
  echo
  echo "Example:"
  echo "CURL_TIMEOUT=40 DEFAULT_MAX_RETRIES=5 ./$(basename "$0") deepseek-r1 cpu-tiny"
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

check_for_yq() {
  if ! command -v yq &>/dev/null; then
    exit_error "yq is required but not installed. Please install yq v4.x and try again."
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

check_exit_code() {
  if [ "$1" -eq 0 ]; then
    log_info "✓ Chat completion: OK"
  else
    exit_error "Chat completion failed (may indicate service issues)"
  fi
}

test_endpoint() {
  local endpoint="$1"
  local description="$2"

  log_info "Testing $description: $endpoint"

  if curl -s --fail-with-body --connect-timeout "$CURL_TIMEOUT" "$endpoint" >/dev/null; then
    log_info "✓ $description: OK"
  else
    exit_error "✗ $description: Failed (HTTP >= 400 or connection error)"
  fi
}

test_chat_completion_openvino() {
  local base_url="$1"
  local base_path="$2"
  local model_name="$3"

  log_info "Testing OpenVINO chat completion endpoint..."

  local system_message="You are a helpful assistant."
  local prompt="Hello!"
  local json_body
  json_body=$(
    cat <<EOF
{
  "model": "$model_name",
  "messages": [
    {
      "role": "developer",
      "content": "$system_message"
    },
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

  echo -e "Chat payload:\n$json_body"

  local api_response
  api_response=$(
    curl -X POST "$base_url/$base_path/chat/completions" \
      -H "Content-Type: application/json" \
      --max-time "$CURL_TIMEOUT" \
      --retry 0 \
      -d "$json_body" \
      --fail-with-body \
      -s \
      2>/dev/null
  )

  check_exit_code $?

  if [ -z "$api_response" ]; then
    exit_error "Empty response from server"
  fi
}

test_chat_completion_llamacpp() {
  local base_url="$1"
  local base_path="$2"
  local model_name="$3"

  log_info "Testing llama.cpp chat completion endpoint..."

  local json_body

  json_body=$(
    cat <<EOF
{
   "model":"$model_name",
   "prompt":"Say this is a test",
   "temperature":0,
   "max_tokens":5
}
EOF
  )

  echo -e "Chat payload:\n$json_body"

  local api_response
  api_response=$(
    curl -X POST "$base_url/$base_path/completions" \
      --max-time "$CURL_TIMEOUT" \
      --retry 0 \
      -H "Content-Type: application/json" \
      -d "$json_body" \
      --fail-with-body \
      -s \
      2>/dev/null
  )

  check_exit_code $?

  if [ -z "$api_response" ]; then
    exit_error "Empty response from server"
  fi
}

test_chat_completion() {
  local base_url="$1"
  local base_path="$2"
  local model_name="$3"
  local server="$4"

  case "$server" in
  "openvino-model-server")
    test_chat_completion_openvino "$base_url" "$base_path" "$model_name"
    ;;
  "llamacpp"*)
    test_chat_completion_llamacpp "$base_url" "$base_path" "$model_name"
    ;;
  *)
    exit_error "Unknown server: $server, add a new test function to this script"
    ;;
  esac
}

run_api_tests() {
  local base_url="$1"
  local base_path="$2"
  local model_name="$3"
  local server="$4"

  log_section "API Endpoint Tests"

  if [[ "$server" == "llamacpp" ]]; then
    # Test models endpoint (ovms does not have this endpoint)
    test_endpoint "$base_url/$base_path/models" "List available models"
  fi

  # Test chat completion
  test_chat_completion "$base_url" "$base_path" "$model_name" "$server"
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

  log_info "Checking all configs (snap get)..."
  snap get "$snap_name" -d

  log_info "Checking all configs (snap command)..."
  "$snap_name" get

  log_info "Getting config subset..."
  default_port=$("$snap_name" get http)

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

  log_info "Reverting configuration change..."
  "$snap_name" set http.port="$default_port"
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

  log_info "Testing engine switch with retry logic..."
  if ! use_engine_with_retry "$snap_name" "$target_engine"; then
    exit_error "Failed to switch to engine: $target_engine"
  fi

  log_info "Verifying engine switch via status command..."
  local curr_engine
  curr_engine=$("$snap_name" status | head -n 1 | cut -d ' ' -f 2)

  if [[ "$curr_engine" != "$target_engine" ]]; then
    exit_error "Current engine from status command ($curr_engine) does not match expected engine ($target_engine)."
  fi
  log_info "✓ Engine switch verified via status command"
}

test_automatic_engine_selection() {
  local snap_name="$1"
  log_section "Automatic engine selection test"

  log_info "Running: $snap_name use-engine --auto"
  "$snap_name" use-engine --auto
  engine=$(sudo "$snap_name" use-engine --auto 2>&1 | grep -oP 'Selected engine for your hardware configuration: \K\S+')

  log_info "Selected engine: $engine"

  snap stop "$snap_name"
  snap start "$snap_name"

  check=$("$snap_name" status 2>&1 | grep -oP 'Using \K\S+')

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
  local base_path
  base_path=$("$snap_name" get http.base-path)
  local base_url="http://localhost:$server_port"
  local model_name
  model_name=$("$snap_name" get model-name 2>/dev/null || true)
  local server
  server=$("$snap_name" show-engine | yq .configurations.server)

  # Pre-flight checks
  check_port_listening "$server_port"

  # Run all test suites
  run_api_tests "$base_url" "$base_path" "$model_name" "$server"
  test_snap_installation "$snap_name"
  test_configuration_management "$snap_name"
  test_engine_listing "$snap_name"
  test_automatic_engine_selection "$snap_name"
  test_engine_switching "$snap_name" "$target_engine"

  log_section "All Smoke Tests Completed Successfully!"
}

# =============================================================================
# SCRIPT ENTRY POINT
# =============================================================================

# Validation
check_root_privileges
check_for_curl
check_for_yq
validate_arguments "$@"

# Extract arguments
AI_SNAP_NAME="$1"
MODEL_ENGINE="$2"

# Run main function
main "$AI_SNAP_NAME" "$MODEL_ENGINE"
