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

2. **Fetch open issues from GitHub** (the repository is public; no token required).

   ```
   curl -s "https://api.github.com/repos/canonical/inference-snaps/issues?state=open&per_page=100"
   ```

   If you get back fewer than 100 issues, one page is enough. If the response contains
   exactly 100 items, fetch the next page by appending `&page=2`, and continue until a
   page returns fewer than 100 items. Collect all open issues before proceeding.

   For each issue keep: number, title, body (first 500 chars is enough), html_url.

3. **Triage each error finding** against the collected issues.

   For each error finding, decide whether an existing open issue describes the same
   underlying problem closely enough that filing a new issue would be a duplicate.
   Use the finding's `title`, `description`, `observed`, and `expected` fields for
   comparison. A match is "close enough" when the existing issue is clearly about the
   same failure mode in the same snap component — not just a vague keyword overlap.

4. **Print the triage report** in this exact format so it is easy to read in CI logs:

   ```
   === ISSUE TRIAGE REPORT ===

   Finding 1: <finding title>
   Status   : DUPLICATE
   Issue    : #<number> — <title>
   URL      : <html_url>
   Reason   : <one sentence explaining why this is the same problem>

   Finding 2: <finding title>
   Status   : NEW
   ---
   Suggested title:
   <A concise GitHub issue title>

   Suggested body:
   ## Description
   <Clear description of what went wrong>

   ## Steps to reproduce
   <Exact commands from finding.reproduction>

   ## Observed behaviour
   <From finding.observed>

   ## Expected behaviour
   <From finding.expected>

   ## Environment
   <From report.environment: snap name, channel, version, revision, arch, os>

   Suggested labels: <comma-separated list from finding.labels>
   ---
   ```

   Print one block per error finding. Use `DUPLICATE` or `NEW` for Status.
   Do not skip any error finding.

5. Write the triage results as JSON to `/tmp/snap-triage-report.json` using this schema:

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
         "suggested_body": "...",
         "suggested_labels": ["bug"]
       },
       {
         "finding_title": "...",
         "status": "DUPLICATE",
         "duplicate_of_number": 42,
         "duplicate_of_url": "https://github.com/canonical/inference-snaps/issues/42",
         "duplicate_reason": "..."
       }
     ]
   }
   ```
