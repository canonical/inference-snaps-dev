# Testflinger tests

Install an inference snap on real hardware with Testflinger and check that it works:
drivers, engine selection, chat prompt with a minimum TPS, and image prompt.

- `agent-scripts/`: the test steps, run by `main.sh`
- `testflinger-jobs/test-snap.yaml`: the Testflinger job, which attaches `../agent-scripts`
- `run.sh`: submit a job from your machine
- `local-scripts/`: run the test over SSH, without Testflinger

## Configuration

The workflow takes inputs, the scripts take the matching environment variables:

| Input | Variable | |
|---|---|---|
| `job-queue` | `JOB_QUEUE` | Testflinger queue |
| `provision-data` | `PROVISION_DATA` | e.g. `distro: noble` |
| `snap-name` | `SNAP_NAME` | |
| `snap-channel` | `SNAP_CHANNEL` | e.g. `latest/edge` |
| `devmode` | `DEVMODE` | install in devmode |
| `install-nvidia-driver-version` | `INSTALL_NVIDIA_DRIVER_VERSION` | e.g. `595`, `latest`. Workflow also accepts `stable` |
| `install-intel-npu-driver` | `INSTALL_INTEL_NPU_DRIVER` | |
| `snap-connections` | `SNAP_CONNECTIONS` | comma separated plugs |
| `expected-engine` | `EXPECTED_ENGINE` | fail if another engine is auto-selected |
| `select-engine` | `SELECT_ENGINE` | engine to switch to |
| `test-chat-tps` | `TEST_CHAT_TPS` | |
| `expected-tps` | `EXPECTED_TPS` | minimum TPS |
| `test-image-prompt` | `TEST_IMAGE_PROMPT` | |

## CI

Snap repos run the tests with the `trigger-tests` PR label, through
[reuse-pr-build-test](../../.github/workflows/reuse-pr-build-test.yaml).
Each entry of `test-jobs-matrix` calls [test-snap](../../.github/workflows/test-snap.yaml).

`test-snap` checks out the test scripts from the same commit as the workflow itself.
To test changes from a snap PR, point the snap's workflow at your branch:

```yaml
uses: canonical/inference-snaps-dev/.github/workflows/reuse-pr-build-test.yaml@<branch>
```

`test-snap` can also be run manually from the Actions tab of this repo.

## From your machine

Submit a job with the same job file as CI. Requires the `testflinger` CLI, `envsubst` (`gettext-base`) and `yq`.

```shell
JOB_QUEUE=maas-systemtests-amd64 SNAP_NAME=smollm2 SNAP_CHANNEL=latest/edge SELECT_ENGINE=cpu \
./tests/testflinger/run.sh
```

`TEST_CHAT_TPS` defaults to `true` and `PROVISION_DATA` to `distro: noble`.
Set `PROVISION_DATA=` to skip provisioning (and the need for `yq`).

## Over SSH, without Testflinger

Set the device and test configuration in `local-scripts/env.bash`, then:

```shell
./tests/testflinger/local-scripts/run-tests.sh
```

The device can be `localhost`. SSH key authentication is required.
