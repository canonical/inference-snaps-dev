# Publish snaps

This Github Action publishes a snap package along with snap components to the Snap Store.

The action sets the snap channel depending on the trigger event. On pull request it sets the channel to `<track>/edge/pr-<number>`, otherwise to `<track>/edge/<short-commit-hash>`.

## Basic Usage

If you wish to define your job inline, you can use the following step:

```yaml
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Build snap
        uses: canonical/action-build@v1

      - name: Publish snap
        uses: canonical/inference-snaps-dev/actions/publish@main
        with:
          store-credentials: ${{ secrets.STORE_LOGIN }}
```

## Store login

This action requires a Snap Store login secret saved in Github as secret. Export a token as `secret.txt` and add its content as a repository secret named `STORE_LOGIN`:

```bash
snapcraft export-login \
    --snaps "<snap-name>" \
    --channels "*/edge/*" \
    --acls package_access,package_push,package_update,package_release \
    --expires 2026-08-15T00:00:00Z \
    secret.txt
```


## Inputs

| Name | Description | Default | Required |
|---|---|---|---|
| `store-credentials` | Snap Store credentials to publish the snap || true |
| `snap-track` | Snap Channel track | `latest` | true |
