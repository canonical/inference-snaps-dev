# Inference Snaps Dev

This project contains developer tools for building, uploading, and testing Inference Snaps.

## Reusable Workflows
A few Reusable Workflows are available in the `.github/workflows` folder:

- [build-publish-snap](./.github/workflows/build-publish-snap.yaml) - to build and publish a snap with its components
- [reuse-cicd](./.github/workflows/reuse-cicd.yaml) - to run CICD on push events from the default branch
- [reuse-pr-build-test](./.github/workflows/reuse-pr-build-test.yaml) - to build or build+test a snap depending on the PR label that triggered it
- [reuse-triage-failures](./.github/workflows/reuse-triage-failures.yaml) - to triage and retry failed jobs classified as failures

## Actions
A few Actions are available in the `.github/actions` folder:

- [agentic-test](./.github/actions/agentic-test/action.yaml) - to run the agentic snap test via Workshop & OpenCode
- [remove-label](./.github/actions/remove-label/action.yaml) - to remove a label from a PR after the associated workflow has run
- [smoke-test](./.github/actions/smoke-test/action.yaml) - to run smoke tests against an installed snap
- [update-ovms](./.github/actions/update-ovms/action.yaml) - to update the pinned OVMS source URL and SHA-256 in `snap/snapcraft.yaml`

### OVMS source updates

The action runs after checkout, uses `gh` (set `GH_TOKEN` to a read-only GitHub token),
and edits only the `openvino-model-server` part. Choose `python-variant: "on"` or
`"off"` to match the snap. It supports the Ubuntu 24 amd64 archive and preserves
other entries in an architecture-conditional source. It selects the newest
stable release numerically, uses the URL and digest from GitHub's uploaded asset,
and fails without editing if the expected archive or digest is missing or
ambiguous. It does not open a PR or publish a snap; the caller owns those steps.
During migration, disable only Renovate's OVMS rule in each consumer before
enabling automated PRs so the two updaters don't compete.

For a branch test, set `release-through` to replay an older release and
`verify-download: "true"` to stream the archive and check its SHA-256 before
writing the update. The action logs the resulting diff.

## Scripts
This project contains a few scripts to help build, install, and upload the snaps:

- [build.sh](./build.sh) - to build the snap and its components
- [install.sh](./install.sh) - to install the built snap
- [upload.sh](./upload.sh) - to upload the built snap to the Snap Store
- [smoke-test.sh](./smoke-test.sh) - to run smoke tests against an installed snap

Add this repo as a submodule to your snap project:
```shell
git submodule add --branch v2 https://github.com/canonical/inference-snaps-dev dev
```

Use the scripts from the root of the snap repo, e.g.:
```
./dev/upload.sh
```
