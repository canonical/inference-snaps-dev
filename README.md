# Famous models dev
Developer tools for the Famouls Model snaps

## Actions
The Github Actions maintained here may be used in workflows within the snaps repos.

* [publish](./actions/publish) - to publish a snap with its components

## Scripts
This project contains a few scripts to help build, install, and upload the snaps.

Add this repo as a submodule to your snap project:
```shell
git submodule add --name famous-models-dev https://github.com/canonical/famous-models-dev dev
```

Use the scripts from the root of the snap repo, e.g.:
```
./dev/upload.sh
```
