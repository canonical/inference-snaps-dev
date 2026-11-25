SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Subscripts can set env vars which are used in following scripts. Therefore call them with source.

# All available tests are listed here. Test conditions are checked in each subscript.

# Use ubuntu for DUT username if DEVICE_USER is not set
export DEVICE_USER="${DEVICE_USER:-ubuntu}"

# Setup
source "${SCRIPT_DIR}/setup-agent.sh"
source "${SCRIPT_DIR}/setup-dut.sh"

# Drivers
source "${SCRIPT_DIR}/install-nvidia-driver.sh"
source "${SCRIPT_DIR}/install-intel-npu-driver.sh"

# Install includes auto engine selection
source "${SCRIPT_DIR}/install-snap.sh"
# Connect interfaces
source "${SCRIPT_DIR}/snap-connections.sh"
# Switch engine
source "${SCRIPT_DIR}/engine-selection.sh"

# Test chat prompt and check TPS
source "${SCRIPT_DIR}/prompt-llm.sh"

# Test image prompt
source "${SCRIPT_DIR}/prompt-vlm.sh" "${SCRIPT_DIR}/circle.jpg"
