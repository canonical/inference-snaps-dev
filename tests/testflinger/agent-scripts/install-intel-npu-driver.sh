#!/bin/bash -eu

if [ "${INSTALL_INTEL_NPU_DRIVER}" != "true" ]; then
  echo "INSTALL_INTEL_NPU_DRIVER is not true; skipping Intel NPU driver installation"
  return 0
fi

echo "::group::Installing Intel NPU driver snap"
_run_retry sudo snap install intel-npu-driver
wait-for-snap-changes
echo "::endgroup::"
