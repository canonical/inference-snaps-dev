# Inference Snaps Dev

This project contains developer tools for building, uploading, and testing Inference Snaps.

## Reusable Workflows
A few Reusable Workflows are available in the `.github/workflows` folder:

- [build-publish-snap](./.github/workflows/build-publish-snap.yaml) - to build and publish a snap with its components

## Actions
A few Actions are available in the `.github/actions` folder:

- [remove-label](./.github/actions/remove-label/action.yaml) - to remove a label from a PR after the associated workflow has run

## Scripts
This project contains a few scripts to help build, install, and upload the snaps.

Add this repo as a submodule to your snap project:
```shell
git submodule add --branch v2 https://github.com/canonical/inference-snaps-dev dev
```

Use the scripts from the root of the snap repo, e.g.:
```
./dev/upload.sh
```
