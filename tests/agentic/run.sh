#!/usr/bin/env bash
set -euo pipefail

export SNAP_NAME="${SNAP_NAME:-smollm2}"
export SNAP_CHANNEL="${SNAP_CHANNEL:-edge}"
export OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"
export OPENROUTER_MODEL="${OPENROUTER_MODEL:-deepseek/deepseek-v4-flash}"

if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
    echo "ERROR: OPENROUTER_API_KEY is not set in this shell." >&2
    echo "Export it first, e.g.: export OPENROUTER_API_KEY=sk-or-..." >&2
    exit 1
fi

# Launch the workshop if it isn't already running.
workshop launch || true
trap 'workshop remove' EXIT

workshop exec --env OPENROUTER_API_KEY="$OPENROUTER_API_KEY" --env OPENROUTER_MODEL="$OPENROUTER_MODEL" --env SNAP_NAME="$SNAP_NAME" --env SNAP_CHANNEL="$SNAP_CHANNEL" --env GITHUB_SERVER_URL="${GITHUB_SERVER_URL:-}" --env GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}" --env GITHUB_RUN_ID="${GITHUB_RUN_ID:-}" -- \
    opencode run --auto --log-level ERROR \
    --model "openrouter/$OPENROUTER_MODEL" \
    "$(cat AGENT.md)" || true

# Pull the JSON report the agent wrote; fall back to a synthetic failure if it is missing.
REPORT_JSON=$(workshop exec -- sh -c 'cat /tmp/snap-test-report.json 2>/dev/null')

if [[ -z "$REPORT_JSON" ]]; then
    echo "ERROR: agent did not write /tmp/snap-test-report.json" >&2
    exit 1
fi

# Validate JSON and extract verdict.
if ! echo "$REPORT_JSON" | jq . > /dev/null 2>&1; then
    echo "ERROR: /tmp/snap-test-report.json is not valid JSON:" >&2
    echo "$REPORT_JSON" >&2
    exit 1
fi

echo "$REPORT_JSON" > snap-test-report.json
echo "=== Agent report ==="
jq . snap-test-report.json

VERDICT=$(jq -r '.verdict // "UNKNOWN"' snap-test-report.json)
SUMMARY=$(jq -r '.summary // "(no summary)"' snap-test-report.json)
ERROR_COUNT=$(jq '[.findings[] | select(.severity == "error")] | length' snap-test-report.json)

echo ""
echo "Verdict : $VERDICT"
echo "Summary : $SUMMARY"
echo "Errors  : $ERROR_COUNT"

# If there are error findings, run the triage agent to compare them against open issues.
if [[ "$ERROR_COUNT" -gt 0 ]]; then
    echo ""
    echo "=== Running issue triage agent ==="
    workshop exec --env OPENROUTER_API_KEY="$OPENROUTER_API_KEY" --env OPENROUTER_MODEL="$OPENROUTER_MODEL" --env GITHUB_SERVER_URL="${GITHUB_SERVER_URL:-}" --env GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}" --env GITHUB_RUN_ID="${GITHUB_RUN_ID:-}" -- \
        opencode run --auto --log-level ERROR \
        --model "openrouter/$OPENROUTER_MODEL" \
        "$(cat TRIAGE.md)" || true

    TRIAGE_JSON=$(workshop exec -- sh -c 'cat /tmp/snap-triage-report.json 2>/dev/null')
    if [[ -n "$TRIAGE_JSON" ]] && echo "$TRIAGE_JSON" | jq . > /dev/null 2>&1; then
        echo "$TRIAGE_JSON" > snap-triage-report.json
        echo ""
        echo "=== Triage report ==="
        jq . snap-triage-report.json
        NEW_COUNT=$(jq '.new_count // 0' snap-triage-report.json)
        DUP_COUNT=$(jq '.duplicate_count // 0' snap-triage-report.json)
        echo ""
        echo "New issues : $NEW_COUNT"
        echo "Duplicates : $DUP_COUNT"
    else
        echo "WARNING: triage agent did not produce a valid /tmp/snap-triage-report.json" >&2
    fi
fi

if [[ "$VERDICT" != "PASS" ]]; then
    echo "Test FAILED" >&2
    exit 1
fi