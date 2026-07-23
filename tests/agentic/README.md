# Agentic Snap Test

An AI-driven end-to-end test for inference snaps. Instead of a fixed test script, an
LLM agent installs the snap the way a real user would, reads its documentation and CLI,
exercises its functionality, and writes a structured JSON report. When the report
contains defects, a second agent triages them against the open issues on the tracker
repo, and the pipeline can then file new GitHub issues and label cross-snap duplicates
automatically.

Everything runs inside a **workshop** — an isolated, disposable machine environment that
gives the agent a real `snapd` and passwordless `sudo`, so it can install and drive the
snap exactly as an end user would.

The agents are driven by [OpenCode](https://opencode.ai), pointed at a model served
through [OpenRouter](https://openrouter.ai).

## Layout

This directory contains the scripts and prompts for the composite GitHub Action whose
definition lives at `.github/actions/agentic-test/action.yaml`.

| Path            | Role                                                                         |
|-----------------|------------------------------------------------------------------------------|
| `run.sh`        | Orchestrator — runs all phases in order and gates on the verdict.            |
| `workshop.yaml` | The workshop definition which includes the OpenCode SDK.                     |
| `scripts/`      | Supporting scripts and prompts executed inside/around the workshop.          |

Inside `scripts/`:

| File                        | Role                                                              |
|-----------------------------|-------------------------------------------------------------------|
| `AGENT.md`                  | Prompt/instructions for the **testing** agent (phase 1).          |
| `TRIAGE.md`                 | Prompt/instructions for the **triage** agent (phase 2).           |
| `run-test-agent.sh`         | Phase 1 — run the testing agent, write `snap-test-report.json`.   |
| `run-triage-agent.sh`       | Phase 2 — run the triage agent, write `snap-triage-report.json`.  |
| `print-duplicate-issues.sh` | Print DUPLICATE findings and the issues they match.               |
| `print-new-issues.sh`       | Dry-run: print NEW findings (title + body) for copy-paste.        |
| `create-new-issues.sh`      | Create mode: file NEW findings as issues in the tracker repo.     |
| `label-duplicate-issues.sh` | Create mode: add this snap's label to shared cross-snap issues.   |

The workshop-generated `.workshop.lock` and the report JSON files are git-ignored.

## Calling it from a workflow

The following example workflow invokes the action with the minimum required inputs:

```yaml
name: Agentic Snap Test

on:
  workflow_dispatch:

jobs:
  ai-test:
    runs-on: ubuntu-latest
    steps:
      - name: Run test
        uses: canonical/inference-snaps-dev/.github/actions/agentic-test
        with:
          snap-name: smollm2
          snap-channel: edge
          create-issues: false
          openrouter-api-key: ${{ secrets.OPENROUTER_API_KEY }}
          issue-create-token: ${{ secrets.ISSUE_CREATE_TOKEN }}
```

### Action inputs

| Input                | Required            | Default                      | Purpose                                                                                                            |
|----------------------|---------------------|------------------------------|--------------------------------------------------------------------------------------------------------------------|
| `snap-name`          | yes                 | —                            | Snap to install and test.                                                                                          |
| `snap-channel`       | no                  | `edge`                       | Store channel to install from (`track/risk/branch`).                                                               |
| `issue-repo`         | no                  | `canonical/inference-snaps`  | Repo where issues are filed / matched.                                                                             |
| `create-issues`      | no                  | `false`                      | `true` files issues for NEW findings and labels cross-snap duplicates; `false` is a dry-run that only prints them. |
| `issue-create-token` | only in create mode | `""`                         | Fine-grained PAT with Issues: read & write on the tracker repo.                                                    |
| `openrouter-model`   | no                  | `deepseek/deepseek-v4-flash` | OpenRouter model used by both agents.                                                                              |
| `openrouter-api-key` | yes                 | —                            | OpenRouter API key used by both agents.                                                                            |

> **Why a separate token?** Issues are filed in a *different* repo than the one running
> the workflow. The default `GITHUB_TOKEN` cannot write cross-repo, so a fine-grained PAT
> is required for `create-issues: true`. In dry-run mode it can be omitted.

### What the action does

The composite action (`.github/actions/agentic-test/action.yaml`) runs these steps:

1. Resolve `TEST_DIR` to the absolute path of `tests/agentic` (three levels up from the
   action's own directory at `.github/actions/agentic-test`).
2. Launch the workshop via the `canonical/launch-workshop@v1` action, pointed at
   `TEST_DIR` (where `workshop.yaml` lives).
3. Run `run.sh` from `TEST_DIR`, mapping the inputs onto the environment
   variables the scripts consume (`SNAP_NAME`, `SNAP_CHANNEL`, `OPENROUTER_API_KEY`,
   `OPENROUTER_MODEL`, `ISSUE_REPO`, `CREATE_ISSUES`, `ISSUE_CREATE_TOKEN`).
4. Upload `snap-test-report.json` as an artifact (always), and `snap-triage-report.json`
   if it exists.

The job fails if the test verdict is not `PASS` — `run.sh` exits non-zero, which
fails the step.

## Running it locally

`run.sh` reproduces the full flow: launch workshop → test → triage → issues → verdict gate → cleanup.

Prerequisites:

- The `workshop` snap installed and available on `PATH`.
- `opencode`, `jq`, and (for create mode) `gh` installed.
- An OpenRouter API key.

Store your secrets in local files (e.g. `openrouter.key`, `issue-create.token`) and pass
them inline so they are never exported to the session or written to shell history.
Run from this directory (`tests/agentic/`):

```bash
# Dry run: test, triage, and print any new/duplicate findings (no writes to GitHub).
OPENROUTER_API_KEY="$(cat openrouter.key)" \
  SNAP_NAME=smollm2 \
  SNAP_CHANNEL=latest/edge \
  ./run.sh
```

To also file issues and label cross-snap duplicates, provide a token and enable create
mode:

```bash
OPENROUTER_API_KEY="$(cat openrouter.key)" \
  ISSUE_CREATE_TOKEN="$(cat issue-create.token)" \
  ISSUE_REPO=canonical/inference-snaps \
  CREATE_ISSUES=true \
  SNAP_NAME=smollm2 \
  SNAP_CHANNEL=latest/edge \
  ./run.sh
```

### Environment variables

`run.sh` reads and re-exports these (with defaults) for its subscripts:

| Variable             | Default                      | Purpose                                                        |
|----------------------|------------------------------|----------------------------------------------------------------|
| `OPENROUTER_API_KEY` | — (required)                 | OpenRouter API key; the script errors out if unset.            |
| `OPENROUTER_MODEL`   | `deepseek/deepseek-v4-flash` | Model both agents run against.                                 |
| `SNAP_NAME`          | `smollm2`                    | Snap to install and test.                                      |
| `SNAP_CHANNEL`       | `edge`                       | Store channel to install from.                                 |
| `ISSUE_REPO`         | `canonical/inference-snaps`  | Repo the triage agent matches against and issues are filed in. |
| `ISSUE_CREATE_TOKEN` | `""`                         | PAT used to create/label issues in `ISSUE_REPO`.               |
| `CREATE_ISSUES`      | `false`                      | Whether to write to GitHub or just print findings.             |

You can also run the phases individually — e.g. `./scripts/run-test-agent.sh` then
`./scripts/run-triage-agent.sh` — which is handy when iterating on `AGENT.md` or `TRIAGE.md`. The
scripts read the reports the agents wrote to `/tmp` inside the workshop and copy them into
this directory.

Outputs written to this directory (git-ignored):

- `snap-test-report.json` — the testing agent's verdict, environment and findings.
- `snap-triage-report.json` — the triage agent's NEW/DUPLICATE classification.
