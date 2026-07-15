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

3. **Fetch issues from GitHub** (the repository is public; no token required).

   Fetch **open** issues first — these are the primary duplicate targets:

   ```
   curl -s "https://api.github.com/repos/canonical/inference-snaps/issues?state=open&per_page=100"
   ```

   Then also fetch **recently closed** issues. Duplicates are frequently reported against
   an *earlier revision* of the snap and then closed once fixed (or closed as duplicates
   themselves), so an open-only search misses them. A root cause that resurfaces on a new
   revision is still the same problem and should be matched to the closed issue:

   ```
   curl -s "https://api.github.com/repos/canonical/inference-snaps/issues?state=closed&per_page=100&sort=updated&direction=desc"
   ```

   For each query: if you get back fewer than 100 issues, one page is enough. If the
   response contains exactly 100 items, fetch the next page by appending `&page=2`, and
   continue until a page returns fewer than 100 items. For the closed query it is enough
   to collect the first two pages (the 200 most recently updated closed issues); older
   closed issues are unlikely to be relevant.

   Collect all fetched issues before proceeding. Track each issue's `state` (`open` or
   `closed`) so you can report it. For each issue keep: number, title, body (first 500
   chars is enough), html_url, state.

4. **Triage each error finding.**

   Match on **root cause**, not surface wording. Two findings describe the same problem
   when they share the same underlying cause, even if the affected command, error text,
   or snap revision differ. In particular, a missing/unconnected interface (e.g.
   `hardware-observe` not auto-connecting) is a single root cause that can surface as
   several different command failures — treat all of them as the same problem.

   4a. **Collapse same-run duplicates first.** Before comparing against GitHub, group the
   run's own error findings by root cause. If several findings share one cause (same
   missing interface, same confinement denial, same crashing component), keep the
   clearest one as the representative and mark the others as duplicates *of that
   representative finding* (Status `DUPLICATE`, and note in the Reason that it duplicates
   another finding in this same run). Do not file multiple GitHub issues for one cause.

   4b. **Compare each representative finding against the collected issues** (open *and*
   recently closed). Decide whether an existing issue describes the same underlying
   problem closely enough that filing a new issue would be a duplicate. Use the finding's
   `title`, `description`, `observed`, and `expected` fields for comparison. A match is
   "close enough" when the existing issue is clearly about the **same failure mode / root
   cause in the same snap component** — for example both are caused by the same interface
   not being connected — even if it was reported on an earlier revision or has since been
   closed. A shared root cause outweighs differences in the exact command or error string.
   Do **not** match on vague keyword overlap alone.

   When the matched issue is **closed**, still mark the finding `DUPLICATE`, record that
   the existing issue is closed, and note in the Reason that the same root cause has
   resurfaced (which may warrant reopening the existing issue rather than filing a new
   one).

5. **Print the triage report** in this exact format so it is easy to read in CI logs:

   ```
   === ISSUE TRIAGE REPORT ===

   Finding 1: <finding title>
   Status   : DUPLICATE
   Issue    : #<number> — <title> [<open|closed>]
   URL      : <html_url>
   Reason   : <one sentence explaining why this is the same root cause; if the issue is
              closed, note that the root cause has resurfaced; if it duplicates another
              finding in this same run, say so instead of citing a GitHub issue>
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

   Suggested labels: <comma-separated list — always includes "bot" and the snap name in the format `snap/<snap name>`>
   Issue type: Bug
   ---

   Finding 2: <finding title>
   Status   : NEW
   ---
   Suggested title:
   <A concise GitHub issue title>

   Suggested body:
   <same structure as above>

   Suggested labels: <comma-separated list — always includes "bot" and the snap name in the format `snap/<snap name>`>
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
         "suggested_labels": ["bot", "snap/smollm2"],
         "issue_type": "Bug"
       },
       {
         "finding_title": "...",
         "status": "DUPLICATE",
         "duplicate_of_number": 42,
         "duplicate_of_url": "https://github.com/canonical/inference-snaps/issues/42",
         "duplicate_of_state": "closed",
         "duplicate_of_finding": null,
         "duplicate_reason": "...",
         "suggested_title": "...",
         "suggested_body": "<issue body using sections from the fetched bug_report.yaml template>",
         "suggested_labels": ["bot", "snap/smollm2"],
         "issue_type": "Bug"
       }
     ]
   }
   ```

   Notes on the duplicate fields:
   - `duplicate_of_state` is `"open"` or `"closed"` when the match is an existing GitHub
     issue; a `"closed"` value signals the root cause has resurfaced and the existing
     issue may need reopening.
   - `duplicate_of_finding` is the `finding_title` of another finding **in this same run**
     when this finding was collapsed as a same-run duplicate (step 4a); in that case
     `duplicate_of_number`/`duplicate_of_url`/`duplicate_of_state` may be null.

