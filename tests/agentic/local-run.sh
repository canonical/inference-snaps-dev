#!/usr/bin/env bash
set -euo pipefail
# ---------------------------------------------------------------------------
# Local convenience wrapper that runs the full agentic snap test end to end:
#   1. test.sh   — run the testing agent, write snap-test-report.json
#   2. triage.sh — triage error findings, write snap-triage-report.json
#   3. new/duplicate issue scripts — print (or create) new issues, summarise
#      duplicates and label cross-snap duplicates from the triage report
#
# In CI these phases run as separate steps of the agentic-test composite action
# (see .github/actions/agentic-test/action.yaml); this wrapper reproduces the
# same flow for local runs, including workshop cleanup and the final verdict gate.
# ---------------------------------------------------------------------------
# Launch the workshop up front and make sure it is always removed on exit,
# regardless of which phase fails.
workshop launch || true
# `|| true` keeps a cleanup failure from overriding the script's real exit
# status (or aborting cleanup) under `set -e`.
trap 'workshop remove || true' EXIT
# Phase 1: testing. test.sh launches the workshop (idempotent) and writes the
# report; it does not remove the workshop or gate the verdict.
./test.sh
VERDICT=$(jq -r '.verdict // "UNKNOWN"' snap-test-report.json)
ERROR_COUNT=$(jq '[.findings[] | select(.severity == "error")] | length' snap-test-report.json)
# Phases 2 & 3 only run when there are error findings to triage / file.
if [[ "$ERROR_COUNT" -gt 0 ]]; then
    ./triage.sh
    ./summarise-duplicate-issues.sh
    # New findings: create them (and label cross-snap duplicates, which write to
    # GitHub) in create mode, otherwise just print them for copy-paste.
    if [[ "${CREATE_ISSUES:-false}" == "true" ]]; then
        ./create-new-issues.sh
        ./label-cross-snap-duplicates.sh
    else
        ./print-new-issues.sh
    fi
fi
if [[ "$VERDICT" != "PASS" ]]; then
    echo "Test FAILED" >&2
    exit 1
fi
