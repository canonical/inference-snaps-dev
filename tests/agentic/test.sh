#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Phase 1: run the testing agent and produce snap-test-report.json.
#
# This script launches the workshop (if not already running) and runs the
# OpenCode testing agent inside it. It writes the agent's JSON report to
# snap-test-report.json in the current directory and exposes the error count
# and verdict as GitHub step outputs so later workflow steps (triage, issues,
# verdict gate) can decide whether to run.
#
# It intentionally does NOT remove the workshop or fail the job on a FAIL
# verdict — that is left to later steps so triage/issue-filing can run first.
# ---------------------------------------------------------------------------

export SNAP_NAME="${SNAP_NAME:-smollm2}"
export SNAP_CHANNEL="${SNAP_CHANNEL:-edge}"
export OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"
export OPENROUTER_MODEL="${OPENROUTER_MODEL:-deepseek/deepseek-v4-flash}"

if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
    echo "ERROR: OPENROUTER_API_KEY is not set in this shell." >&2
    echo "Export it first, e.g.: export OPENROUTER_API_KEY=sk-or-..." >&2
    exit 1
fi

# Launch the workshop if it isn't already running. It is removed by a later
# workflow step (or by local-run.sh's trap when run locally), so we do NOT remove it
# here — later steps reuse the same running workshop.
workshop launch || true

echo "::group::Testing Agent Output"
workshop exec --env OPENROUTER_API_KEY="$OPENROUTER_API_KEY" --env OPENROUTER_MODEL="$OPENROUTER_MODEL" --env SNAP_NAME="$SNAP_NAME" --env SNAP_CHANNEL="$SNAP_CHANNEL" --env GITHUB_SERVER_URL="${GITHUB_SERVER_URL:-}" --env GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}" --env GITHUB_RUN_ID="${GITHUB_RUN_ID:-}" -- \
    opencode run --auto --log-level ERROR \
    --model "openrouter/$OPENROUTER_MODEL" \
    "$(cat AGENT.md)" || true
echo "::endgroup::"

# Pull the JSON report the agent wrote; fail if it is missing.
# `|| true` keeps a failing workshop exec (e.g. missing report file) from
# aborting the script under `set -e` before the explicit emptiness check below.
REPORT_JSON=$(workshop exec -- sh -c 'cat /tmp/snap-test-report.json 2>/dev/null' || true)

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

echo "::group::Test Report (JSON)"
jq . snap-test-report.json
echo "::endgroup::"

VERDICT=$(jq -r '.verdict // "UNKNOWN"' snap-test-report.json)
SUMMARY=$(jq -r '.summary // "(no summary)"' snap-test-report.json)
ERROR_COUNT=$(jq '[.findings[] | select(.severity == "error")] | length' snap-test-report.json)

echo ""
echo "Verdict : $VERDICT"
echo "Summary : $SUMMARY"
echo "Errors  : $ERROR_COUNT"

# Expose the verdict and error count to subsequent workflow steps so they can
# gate on them (e.g. only triage when there are error findings).
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
        echo "verdict=$VERDICT"
        echo "error_count=$ERROR_COUNT"
    } >> "$GITHUB_OUTPUT"
fi

