#!/usr/bin/env bash
set -euo pipefail
# ---------------------------------------------------------------------------
# Local convenience wrapper that runs the full agentic snap test end to end:
#   1. test.sh   — run the testing agent, write snap-test-report.json
#   2. triage.sh — triage error findings, write snap-triage-report.json
#   3. issues.sh — print / create / label GitHub issues from the triage report
#
# In CI these phases run as separate workflow steps (see
# .github/workflows/reuse-agentic-test.yaml); this wrapper reproduces the same
# flow for local runs, including workshop cleanup and the final verdict gate.
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
    ./issues.sh
fi
if [[ "$VERDICT" != "PASS" ]]; then
    echo "Test FAILED" >&2
    exit 1
fi
