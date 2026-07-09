#!/usr/bin/env bash
set -euo pipefail

export SNAP_NAME="${SNAP_NAME:-smollm2}"
export SNAP_CHANNEL="${SNAP_CHANNEL:-edge}"
export OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"
export OPENROUTER_MODEL="${OPENROUTER_MODEL:-openrouter/openrouter/free}"

if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
    echo "ERROR: OPENROUTER_API_KEY is not set in this shell." >&2
    echo "Export it first, e.g.: export OPENROUTER_API_KEY=sk-or-..." >&2
    exit 1
fi

# Launch the workshop if it isn't already running.
workshop launch || true

workshop exec --env OPENROUTER_API_KEY="$OPENROUTER_API_KEY" --env OPENROUTER_MODEL="$OPENROUTER_MODEL" --env SNAP_NAME="$SNAP_NAME" --env SNAP_CHANNEL="$SNAP_CHANNEL" -- \
    opencode run --auto --log-level ERROR \
    --model "$OPENROUTER_MODEL" \
    "Follow the instructions in AGENT.md."
