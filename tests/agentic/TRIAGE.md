# Issue Triage Agent Instructions

Your job is to compare the error findings from a snap test run against the currently open
issues on the `canonical/inference-snaps` GitHub repository, and report which findings
are already tracked and which are new.

## Steps

1. **Read the test report.**

   ```
   cat /tmp/snap-test-report.json
   ```

   Extract only the findings with `"severity": "error"`. If there are none, print
   "No error findings — nothing to triage." and stop.

2. **Fetch the bug report issue template** from the repository so your suggested bodies
   always match the current template structure.

   ```
   curl -s "https://raw.githubusercontent.com/canonical/inference-snaps/main/.github/ISSUE_TEMPLATE/bug_report.yaml"
   ```

   Read the `body` fields to understand what sections are expected and in what order.
   Use the `label`, `description`, and `value` of each field to guide how you fill in
   the content for each finding.

3. **Fetch open issues from GitHub** (the repository is public; no token required).

   ```
   curl -s "https://api.github.com/repos/canonical/inference-snaps/issues?state=open&per_page=100"
   ```

   If you get back fewer than 100 issues, one page is enough. If the response contains
   exactly 100 items, fetch the next page by appending `&page=2`, and continue until a
   page returns fewer than 100 items. Collect all open issues before proceeding.

   For each issue keep: number, title, body (first 500 chars is enough), html_url.

4. **Triage each error finding** against the collected issues.

   For each error finding, decide whether an existing open issue describes the same
   underlying problem closely enough that filing a new issue would be a duplicate.
   Use the finding's `title`, `description`, `observed`, and `expected` fields for
   comparison. A match is "close enough" when the existing issue is clearly about the
   same failure mode in the same snap component — not just a vague keyword overlap.

5. **Print the triage report** in this exact format so it is easy to read in CI logs:

   ```
   === ISSUE TRIAGE REPORT ===

   Finding 1: <finding title>
   Status   : DUPLICATE
   Issue    : #<number> — <title>
   URL      : <html_url>
   Reason   : <one sentence explaining why this is the same problem>
   ---
   Suggested title:
   <A concise GitHub issue title>

   Suggested body:
   <Issue body filled in using the section structure from the fetched bug_report.yaml
   template. Populate each field using the finding and report data:
   - Bug description    ← finding.description, then observed vs expected behaviour;
                          if report.environment.ci_run_url is non-null, append a line:
                          "Detected by CI run: <ci_run_url>"
   - To reproduce       ← finding.reproduction
   - Snap version       ← report.environment.snap_list_output (as a shell code block)
   - System information ← report.environment.show_machine_output (wrapped in the
                          <details> block the template specifies)>

   Suggested labels: <comma-separated list — always includes "bot" and the snap name>
   Issue type: Bug
   ---

   Finding 2: <finding title>
   Status   : NEW
   ---
   Suggested title:
   <A concise GitHub issue title>

   Suggested body:
   <same structure as above>

   Suggested labels: <comma-separated list — always includes "bot" and the snap name>
   Issue type: Bug
   ---
   ```

   Print one block per error finding. Use `DUPLICATE` or `NEW` for Status.
   Always include the suggested title, body, and labels regardless of status — for
   duplicates this makes it easy to update the existing issue with fresh reproduction
   steps and environment details.
   Do not skip any error finding.

6. Write the triage results as JSON to `/tmp/snap-triage-report.json` using this schema:

   ```json
   {
     "findings_triaged": 2,
     "new_count": 1,
     "duplicate_count": 1,
     "results": [
       {
         "finding_title": "...",
         "status": "NEW",
         "suggested_title": "...",
         "suggested_body": "<issue body using sections from the fetched bug_report.yaml template>",
         "suggested_labels": ["bot", "smollm2"],
         "issue_type": "Bug"
       },
       {
         "finding_title": "...",
         "status": "DUPLICATE",
         "duplicate_of_number": 42,
         "duplicate_of_url": "https://github.com/canonical/inference-snaps/issues/42",
         "duplicate_reason": "...",
         "suggested_title": "...",
         "suggested_body": "<issue body using sections from the fetched bug_report.yaml template>",
         "suggested_labels": ["bot", "smollm2"],
         "issue_type": "Bug"
       }
     ]
   }
   ```
