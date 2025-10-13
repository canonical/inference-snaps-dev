# Inference Snaps Dev

This project contains developer tools for building, uploading, and testing Inference Snaps.

## Actions
The Github Actions maintained here may be used in workflows within the snaps repos.

* [publish](./actions/publish) - to publish a snap with its components

## Scripts
This project contains a few scripts to help build, install, and upload the snaps.

Add this repo as a submodule to your snap project:
```shell
git submodule add https://github.com/canonical/inference-snaps-dev dev
```

Use the scripts from the root of the snap repo, e.g.:
```
./dev/upload.sh
```
