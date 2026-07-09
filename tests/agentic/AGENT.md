# CI Testing Agent Instructions

You are a user of our snap, testing the `$SNAP_NAME` inference snap installed from the
Snap Store channel `$SNAP_CHANNEL`.

This is an inference snap. These snaps are documented at
https://documentation.ubuntu.com/inference-snaps. Read the documentation to learn how
to install and use them before you start.

Your job is to test the snap the way a real user would and to **actively detect and
report problems** — not to make the test pass. A green result is only valid if the snap
genuinely works as documented.

## Environment
- `$SNAP_NAME` — name of the snap to install.
- `$SNAP_CHANNEL` — store channel to install from (may include a track/risk/branch).

## Setup

You have a working `snapd` and passwordless `sudo`, so install and use the snap exactly
as a real user would.

> **Important — this is a non-interactive shell with no TTY.** Your commands do not run
> against a real terminal. This has three consequences you MUST account for, otherwise
> you will report bugs that do not exist:
>
> 1. **Output capture — run CLI commands through a PTY.** The snap CLI is launched via
>    `snap run` and only produces its normal output when attached to a terminal. In this
>    shell a bare invocation may appear to print nothing. To test the CLI the way a real
>    user sees it, wrap every `"$SNAP_NAME" …` command in a pseudo-terminal using
>    `script`:
>    ```
>    script -qec '"$SNAP_NAME" <subcommand>' /dev/null
>    ```
>    `script` allocates a PTY, runs the command inside it, and writes everything the user
>    would see to stdout (discarding the typescript to `/dev/null`). Use this whenever you
>    need to read and verify a command's output. A command appearing to print nothing
>    when run *without* `script` is a harness artifact, **not** a snap defect — never
>    report it as one.
> 2. **Interactive prompts.** Some commands ask for confirmation before making a change.
>    Run bare here they will **hang forever**, because there is no terminal to read from.
>    Exercise them two ways:
>    - **Non-interactively** with the documented `--assume-yes` flag (or whatever
>      equivalent the snap documents).
>    - **Interactively, as a real user would**, by feeding the answer into the PTY that
>      `script` creates:
>      ```
>      printf 'y\n' | script -qec '"$SNAP_NAME" <subcommand>' /dev/null
>      ```
>      `script` forwards its stdin to the prompt, so the command sees `y` (or `n`) just
>      as if you had typed it. Test **both** a `y` answer (the action proceeds) and an
>      `n` answer (the action is cancelled), and verify each behaves correctly.
>
>    Do NOT feed a prompt with `echo y |` or `yes |` **without** `script` — that does
>    not work because the prompt reads the terminal, not stdin, and the command will
>    hang. A hang in that case is a harness limitation, not a snap bug.
> 3. **Exit codes.** Check the exit status of the command **itself**, on its own line:
>    ```
>    "$SNAP_NAME" <subcommand>
>    echo "exit=$?"
>    ```
>    Do NOT prefix the command with `echo ... |` and do NOT use `${PIPESTATUS[0]}` to
>    read a command that is not first in a pipeline — you will measure the wrong
>    process's exit code. When you wrap a command in `script`, note that `script`'s exit
>    code reflects the wrapped command's exit code, so `script -qec '…' /dev/null; echo
>    "exit=$?"` is a reliable way to capture both output and status together.

1. Install the snap from the requested channel, passing the channel string exactly as
   given. **Installing can take several minutes** because the snap also downloads and
   installs large engine/model *components* after the snap itself. Kick the install off
   without blocking, then poll until snapd reports it finished:

   ```
   sudo snap install "$SNAP_NAME" --channel="$SNAP_CHANNEL" --no-wait
   # Wait for snapd to finish. This continues in the background even if a single command
   # times out, so poll in short steps rather than waiting in one long-running command.
   # Loop while any change for the snap is still in progress:
   while snap changes "$SNAP_NAME" | grep -qE '^[0-9]+ +(Do|Doing|Undo|Undoing|Wait) '; do
       snap changes "$SNAP_NAME" | tail -n 3
       sleep 15
   done
   snap changes "$SNAP_NAME" | tail -n 5
   ```

   > **Do not treat a slow or timed-out install as a failure.** `snap install` continues
   > inside snapd even if your foreground command is cut off by the harness timeout. While
   > it runs, a partially-installed state is completely normal — `snap list` may show
   > `components[1/3]`, `snap components "$SNAP_NAME"` may list some components as still
   > `available` (not yet `installed`), and the service will log
   > "Waiting for required snap components". This is expected progress, **not** a defect.
   >
   > **Never** `snap abort` the install change, and **never** work around it by manually
   > installing components (e.g. `snap install "$SNAP_NAME"+<component>`). Let the normal
   > install finish on its own. Only after the install change reaches `Done` should you
   > continue — then confirm the components required for your setup are `installed`:
   >
   > ```
   > snap components "$SNAP_NAME"
   > ```
   >
   > **Not every component listed is required.** A snap bundles components for multiple
   > engines/models and hardware types, and only the subset needed for the **selected
   > engine and model** on this machine is installed. It is normal and correct for the
   > others to stay `available` rather than `installed`. Components for unavailable
   > hardware (e.g. a CUDA engine component on a machine without an NVIDIA GPU) will
   > legitimately not be installed — that is expected, not a failure.
   >
   > Only treat this as a genuine defect if the install change ends in `Error`, or if a
   > component that *is* required for the selected engine and model is still missing after
   > the change completes.

2. Confirm it installed and inspect its interface connections:

   ```
   snap list "$SNAP_NAME"
   snap connections "$SNAP_NAME"
   ```

   These snaps are strictly confined, so some interfaces (plugs) may not auto-connect.
   This is expected and is only a real problem if it actually prevents the snap from
   working. If, and only if, something you test fails because of a missing connection,
   connect it with `sudo snap connect "$SNAP_NAME":<plug>` and note that it was required.
   Do not fail the run solely because a plug is unconnected while the snap still works.

3. Discover the available commands before using them, running the CLI through a PTY so
   its output is captured:

   ```
   script -qec '"$SNAP_NAME" --help' /dev/null
   ```

## What to test

Use the documentation and the snap's own `--help` output to work out what this snap is
for and how a user is meant to use it. Then exercise it as a user would, covering the
functionality it advertises. There is no fixed checklist — explore broadly rather than
following a script, so you notice anything that is wrong or missing.

Approach it like a curious user:

- Build a picture of the snap's purpose and its full set of commands/options from the
  docs and `--help`, then actually try them.
- For everything you run, read the output (through a PTY) and check it looks correct —
  expected content present, values sensible, no unexpected errors — rather than only
  checking the exit code.
- Confirm the snap's main purpose works end to end, including any background services or
  endpoints it relies on.
- Where the snap offers alternatives or options (modes, backends, models, settings, …),
  try switching between them and confirm the change actually takes effect.
- Allow for reasonable limitations of the environment (e.g. shared CI hardware, or
  lower output quality from a small model). Judge whether the snap behaves as its docs
  say it should, and note anything that does not.

## Reporting and exit codes

End your run with a clear **PASS/FAIL** summary. Report a genuine problem for any error,
crash, incorrect or unexpected output, missing functionality, or clearly unreasonable
behaviour. For every problem include:

1. **What went wrong** — a clear description of the failure and what you were testing.
2. **How to reproduce it** — the exact commands you ran, in order, including the channel
   (`$SNAP_CHANNEL`).
3. **Observed vs. expected behaviour** — command output, error messages, and what you
   expected instead.
4. **Environment details** — installed snap version and revision
   (`snap info "$SNAP_NAME"`), runner architecture (`uname -m`), and any relevant
   configuration the snap was using.

Exit **0** only if the snap genuinely works as documented, with no unresolved problems.
Exit **1** if anything failed or could not be verified.
