#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Phase 3: print, create and cross-snap-label GitHub issues from the triage
# report (snap-triage-report.json).
#
# - Prints each triaged finding in its own collapsible CI group for copy-paste.
# - Creates GitHub issues for NEW findings in $ISSUE_REPO (when CREATE_ISSUES=true).
# - Adds this snap's label to existing issues that a finding duplicates but that
#   were originally detected on a different snap (cross-snap duplicates).
#
# Issues are filed in a *different* repo than the one running this workflow, so a
# fine-grained PAT scoped to $ISSUE_REPO (Issues: read & write) is required — the
# default GITHUB_TOKEN cannot write cross-repo.
# ---------------------------------------------------------------------------

export SNAP_NAME="${SNAP_NAME:-smollm2}"
export ISSUE_REPO="${ISSUE_REPO:-canonical/inference-snaps}"
export ISSUE_CREATE_TOKEN="${ISSUE_CREATE_TOKEN:-}"
# Gate: only actually create issues when explicitly enabled (default: dry-run/log only).
export CREATE_ISSUES="${CREATE_ISSUES:-false}"

if [[ ! -f snap-triage-report.json ]]; then
    echo "ERROR: snap-triage-report.json not found; run triage.sh first." >&2
    exit 1
fi

NEW_COUNT=$(jq '.new_count // 0' snap-triage-report.json)
DUP_COUNT=$(jq '.duplicate_count // 0' snap-triage-report.json)

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

        # Guard against missing fields: jq -r prints the literal "null" for an
        # absent key, which would otherwise file a malformed issue.
        if [[ -z "$ISSUE_TITLE" || "$ISSUE_TITLE" == "null" ]]; then
            echo "SKIPPED: result[$i] has no suggested_title; not creating an issue." >&2
            FAILED=$((FAILED + 1))
            continue
        fi
        if [[ -z "$ISSUE_BODY" || "$ISSUE_BODY" == "null" ]]; then
            echo "SKIPPED: '$ISSUE_TITLE' has no suggested_body; not creating an issue." >&2
            FAILED=$((FAILED + 1))
            continue
        fi

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

