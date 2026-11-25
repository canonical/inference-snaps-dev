#!/bin/bash -eux
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Setting configuration variables"
source "${SCRIPT_DIR}/env.bash"

"${SCRIPT_DIR}"/../agent-scripts/main.sh
