#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Phase 2: run the triage agent and produce snap-triage-report.json.
#
# This step compares the error findings in snap-test-report.json against the
# open GitHub issues and classifies each as NEW or DUPLICATE. It reuses the
# workshop already launched by test.sh and reads the test report the agent
# wrote to /tmp inside the workshop.
#
# It only makes sense to run this when the test report contains error
# findings; the workflow gates it on test.sh's error_count output.
# ---------------------------------------------------------------------------

export OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"
export OPENROUTER_MODEL="${OPENROUTER_MODEL:-deepseek/deepseek-v4-flash}"
# Tracker repo the triage agent compares findings against; keep it consistent
# with the workflow's `issue-repo` input and issues.sh's default.
export ISSUE_REPO="${ISSUE_REPO:-canonical/inference-snaps}"

if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
    echo "ERROR: OPENROUTER_API_KEY is not set in this shell." >&2
    exit 1
fi

if [[ ! -f snap-test-report.json ]]; then
    echo "ERROR: snap-test-report.json not found; run test.sh first." >&2
    exit 1
fi

echo "::group::Triage Agent Output"
workshop exec --env OPENROUTER_API_KEY="$OPENROUTER_API_KEY" --env OPENROUTER_MODEL="$OPENROUTER_MODEL" --env ISSUE_REPO="$ISSUE_REPO" --env GITHUB_SERVER_URL="${GITHUB_SERVER_URL:-}" --env GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}" --env GITHUB_RUN_ID="${GITHUB_RUN_ID:-}" -- \
    opencode run --auto --log-level ERROR \
    --model "openrouter/$OPENROUTER_MODEL" \
    "$(cat TRIAGE.md)" || true
echo "::endgroup::"

# `|| true` keeps a failing workshop exec (e.g. missing report file) from
# aborting the script under `set -e` before the JSON validity check below.
TRIAGE_JSON=$(workshop exec -- sh -c 'cat /tmp/snap-triage-report.json 2>/dev/null' || true)
if [[ -z "$TRIAGE_JSON" ]] || ! echo "$TRIAGE_JSON" | jq . > /dev/null 2>&1; then
    echo "ERROR: triage agent did not produce a valid /tmp/snap-triage-report.json" >&2
    exit 1
fi

echo "$TRIAGE_JSON" > snap-triage-report.json

echo "::group::Triage Report (JSON)"
jq . snap-triage-report.json
echo "::endgroup::"

NEW_COUNT=$(jq '.new_count // 0' snap-triage-report.json)
DUP_COUNT=$(jq '.duplicate_count // 0' snap-triage-report.json)
echo ""
echo "New issues : $NEW_COUNT"
echo "Duplicates : $DUP_COUNT"

