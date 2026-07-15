#!/usr/bin/env bash
set -euo pipefail

export SNAP_NAME="${SNAP_NAME:-smollm2}"
export SNAP_CHANNEL="${SNAP_CHANNEL:-edge}"
export OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"
export OPENROUTER_MODEL="${OPENROUTER_MODEL:-deepseek/deepseek-v4-flash}"

# Issue creation config. Issues are filed in a *different* repo than the one running
# this workflow, so a fine-grained PAT scoped to $ISSUE_REPO (Issues: read & write) is
# required — the default GITHUB_TOKEN cannot write cross-repo.
export ISSUE_REPO="${ISSUE_REPO:-canonical/inference-snaps}"
export ISSUE_CREATE_TOKEN="${ISSUE_CREATE_TOKEN:-}"
# Gate: only actually create issues when explicitly enabled (default: dry-run/log only).
export CREATE_ISSUES="${CREATE_ISSUES:-false}"

if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
    echo "ERROR: OPENROUTER_API_KEY is not set in this shell." >&2
    echo "Export it first, e.g.: export OPENROUTER_API_KEY=sk-or-..." >&2
    exit 1
fi

# Launch the workshop if it isn't already running.
workshop launch || true
trap 'workshop remove' EXIT

echo "::group::Testing Agent Output"
workshop exec --env OPENROUTER_API_KEY="$OPENROUTER_API_KEY" --env OPENROUTER_MODEL="$OPENROUTER_MODEL" --env SNAP_NAME="$SNAP_NAME" --env SNAP_CHANNEL="$SNAP_CHANNEL" --env GITHUB_SERVER_URL="${GITHUB_SERVER_URL:-}" --env GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}" --env GITHUB_RUN_ID="${GITHUB_RUN_ID:-}" -- \
    opencode run --auto --log-level ERROR \
    --model "openrouter/$OPENROUTER_MODEL" \
    "$(cat AGENT.md)" || true
echo "::endgroup::"

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

# If there are error findings, run the triage agent to compare them against open issues.
if [[ "$ERROR_COUNT" -gt 0 ]]; then
    echo ""
    echo "::group::Triage Agent Output"
    workshop exec --env OPENROUTER_API_KEY="$OPENROUTER_API_KEY" --env OPENROUTER_MODEL="$OPENROUTER_MODEL" --env GITHUB_SERVER_URL="${GITHUB_SERVER_URL:-}" --env GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}" --env GITHUB_RUN_ID="${GITHUB_RUN_ID:-}" -- \
        opencode run --auto --log-level ERROR \
        --model "openrouter/$OPENROUTER_MODEL" \
        "$(cat TRIAGE.md)" || true
    echo "::endgroup::"

    TRIAGE_JSON=$(workshop exec -- sh -c 'cat /tmp/snap-triage-report.json 2>/dev/null')
    if [[ -n "$TRIAGE_JSON" ]] && echo "$TRIAGE_JSON" | jq . > /dev/null 2>&1; then
        echo "$TRIAGE_JSON" > snap-triage-report.json

        echo "::group::Triage Report (JSON)"
        jq . snap-triage-report.json
        echo "::endgroup::"

        NEW_COUNT=$(jq '.new_count // 0' snap-triage-report.json)
        DUP_COUNT=$(jq '.duplicate_count // 0' snap-triage-report.json)
        echo ""
        echo "New issues : $NEW_COUNT"
        echo "Duplicates : $DUP_COUNT"

        # Print each issue in its own collapsible group for easy copy-paste
        RESULT_COUNT=$(jq '.results | length' snap-triage-report.json)
        for i in $(seq 0 $((RESULT_COUNT - 1))); do
            ISSUE_TITLE=$(jq -r ".results[$i].suggested_title" snap-triage-report.json)
            ISSUE_STATUS=$(jq -r ".results[$i].status" snap-triage-report.json)
            echo ""
            echo "::group::[$ISSUE_STATUS] $ISSUE_TITLE"
            echo "Title: $ISSUE_TITLE"
            if [[ "$ISSUE_STATUS" == "DUPLICATE" ]]; then
                echo ""
                echo "Duplicate of: $(jq -r ".results[$i].duplicate_of_url // \"(unknown)\"" snap-triage-report.json)"
                echo "Reason      : $(jq -r ".results[$i].duplicate_reason // \"(unknown)\"" snap-triage-report.json)"
            fi
            echo ""
            echo "Body:"
            echo "------------------------------------------------------------------------"
            jq -r ".results[$i].suggested_body" snap-triage-report.json
            echo "------------------------------------------------------------------------"
            echo "::endgroup::"
        done

        # ---------------------------------------------------------------------
        # Create GitHub issues for NEW findings in the tracker repo ($ISSUE_REPO).
        # Duplicates are intentionally left as log-only (see triage report above).
        # ---------------------------------------------------------------------
        NEW_INDICES=$(jq -r '[.results | to_entries[] | select(.value.status == "NEW") | .key] | .[]' snap-triage-report.json)

        if [[ "$CREATE_ISSUES" != "true" ]]; then
            if [[ -n "$NEW_INDICES" ]]; then
                echo ""
                echo "Issue creation is disabled (create_issues=false); $NEW_COUNT NEW finding(s) were NOT filed."
                echo "Re-run the workflow with create_issues=true to file them in $ISSUE_REPO."
            fi
        elif [[ -z "${ISSUE_CREATE_TOKEN}" ]]; then
            echo ""
            echo "WARNING: create_issues=true but ISSUE_CREATE_TOKEN is empty; cannot create issues in $ISSUE_REPO." >&2
            echo "Set the ISSUE_CREATE_TOKEN secret (fine-grained PAT with Issues: read & write on $ISSUE_REPO)." >&2
        elif [[ -z "$NEW_INDICES" ]]; then
            echo ""
            echo "No NEW findings to file — nothing to create in $ISSUE_REPO."
        else
            echo ""
            echo "::group::Creating GitHub issues in $ISSUE_REPO"
            CREATED=0
            FAILED=0
            for i in $NEW_INDICES; do
                ISSUE_TITLE=$(jq -r ".results[$i].suggested_title" snap-triage-report.json)
                ISSUE_BODY=$(jq -r ".results[$i].suggested_body" snap-triage-report.json)

                # Step 1: create the issue with gh's builtin flags (auth, base URL and
                # versioning are handled for us; GH_TOKEN scopes it to the cross-repo PAT).
                if ISSUE_URL=$(GH_TOKEN="$ISSUE_CREATE_TOKEN" gh issue create \
                    --repo "$ISSUE_REPO" \
                    --title "$ISSUE_TITLE" \
                    --body "$ISSUE_BODY" \
                    --label "bot" \
                    --label "snap/$SNAP_NAME" 2>/tmp/gh-issue-err); then
                    echo "Created: $ISSUE_URL  ($ISSUE_TITLE)"
                    CREATED=$((CREATED + 1))

                    # Step 2: set the issue type (gh issue create has no --type flag,
                    # so patch it via the API). Non-fatal: warn but keep the issue.
                    ISSUE_NUMBER=$(basename "$ISSUE_URL")
                    if ! GH_TOKEN="$ISSUE_CREATE_TOKEN" gh api --method PATCH \
                        "repos/$ISSUE_REPO/issues/$ISSUE_NUMBER" -f type=Bug \
                        >/dev/null 2>/tmp/gh-type-err; then
                        ERR_MSG=$(jq -r '.message // empty' /tmp/gh-type-err 2>/dev/null)
                        ERR_MSG=${ERR_MSG:-$(cat /tmp/gh-type-err 2>/dev/null || echo "unknown error")}
                        echo "WARNING: created $ISSUE_URL but failed to set type=Bug — $ERR_MSG" >&2
                    fi
                else
                    ERR_MSG=$(cat /tmp/gh-issue-err 2>/dev/null || echo "unknown error")
                    echo "FAILED: $ISSUE_TITLE — $ERR_MSG" >&2
                    FAILED=$((FAILED + 1))
                fi
            done
            echo ""
            echo "Issues created : $CREATED"
            echo "Issues failed  : $FAILED"
            echo "::endgroup::"

            if [[ "$FAILED" -gt 0 ]]; then
                echo "WARNING: $FAILED issue(s) could not be created in $ISSUE_REPO." >&2
            fi
        fi

        # ---------------------------------------------------------------------
        # Cross-snap duplicates: when a finding duplicates an *existing* issue that
        # was originally detected on a different snap (its labels contain some
        # snap/<other> label but not our snap/$SNAP_NAME label), add our snap label
        # to that issue so the tracker records every snap affected by the same bug.
        # ---------------------------------------------------------------------
        CROSS_SNAP_INDICES=$(jq -r --arg snap_label "snap/$SNAP_NAME" '
            [.results | to_entries[]
             | select(.value.status == "DUPLICATE"
                      and .value.duplicate_of_number != null
                      and ((.value.duplicate_of_labels // []) | any(startswith("snap/")))
                      and ((.value.duplicate_of_labels // []) | index($snap_label) | not))
             | .key] | .[]' snap-triage-report.json)

        if [[ "$CREATE_ISSUES" != "true" ]]; then
            if [[ -n "$CROSS_SNAP_INDICES" ]]; then
                echo ""
                echo "Issue creation is disabled (create_issues=false); did not add 'snap/$SNAP_NAME' to cross-snap duplicate issue(s)."
                echo "Re-run the workflow with create_issues=true to label them in $ISSUE_REPO."
            fi
        elif [[ -z "${ISSUE_CREATE_TOKEN}" ]]; then
            if [[ -n "$CROSS_SNAP_INDICES" ]]; then
                echo ""
                echo "WARNING: create_issues=true but ISSUE_CREATE_TOKEN is empty; cannot label cross-snap duplicate issues in $ISSUE_REPO." >&2
            fi
        elif [[ -n "$CROSS_SNAP_INDICES" ]]; then
            echo ""
            echo "::group::Labelling cross-snap duplicate issues in $ISSUE_REPO"
            LABELLED=0
            LABEL_FAILED=0
            for i in $CROSS_SNAP_INDICES; do
                ISSUE_NUMBER=$(jq -r ".results[$i].duplicate_of_number" snap-triage-report.json)
                ISSUE_URL=$(jq -r ".results[$i].duplicate_of_url // \"(unknown)\"" snap-triage-report.json)

                if GH_TOKEN="$ISSUE_CREATE_TOKEN" gh issue edit "$ISSUE_NUMBER" \
                    --repo "$ISSUE_REPO" --add-label "snap/$SNAP_NAME" >/dev/null 2>/tmp/gh-label-err; then
                    echo "Labelled: $ISSUE_URL  (added snap/$SNAP_NAME)"
                    LABELLED=$((LABELLED + 1))
                else
                    ERR_MSG=$(cat /tmp/gh-label-err 2>/dev/null || echo "unknown error")
                    echo "FAILED: $ISSUE_URL — $ERR_MSG" >&2
                    LABEL_FAILED=$((LABEL_FAILED + 1))
                fi
            done
            echo ""
            echo "Issues labelled : $LABELLED"
            echo "Labels failed   : $LABEL_FAILED"
            echo "::endgroup::"

            if [[ "$LABEL_FAILED" -gt 0 ]]; then
                echo "WARNING: $LABEL_FAILED cross-snap duplicate(s) could not be labelled in $ISSUE_REPO." >&2
            fi
        fi
    else
        echo "WARNING: triage agent did not produce a valid /tmp/snap-triage-report.json" >&2
    fi
fi

if [[ "$VERDICT" != "PASS" ]]; then
    echo "Test FAILED" >&2
    exit 1
fi