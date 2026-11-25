#!/bin/bash -eu

if [[ -z "${INSTALL_NVIDIA_DRIVER_VERSION}" ]]; then
  echo "INSTALL_NVIDIA_DRIVER_VERSION is not set; skipping NVIDIA driver installation"
  return 0
fi

_run_retry sudo apt-get update

echo "Preparing to install NVIDIA driver $INSTALL_NVIDIA_DRIVER_VERSION"
driver_version="$INSTALL_NVIDIA_DRIVER_VERSION"
if [[ "$driver_version" == "latest" ]]; then
  driver_package=$(_run "apt list 'nvidia-driver-*' 2>/dev/null | grep -E '^nvidia-driver-[0-9]+/' | tail -n1 | cut -d/ -f1")
  echo "Resolved latest NVIDIA driver package: $driver_package"
  if [[ ! "$driver_package" =~ ^nvidia-driver-([0-9]+)$ ]]; then
    echo "Could not resolve the latest NVIDIA driver package from apt list"
    exit 1
  fi
  driver_version="${BASH_REMATCH[1]}"
fi

echo "::group::Installing NVIDIA driver $driver_version"
_run_retry sudo apt-get install -y nvidia-driver-"$driver_version"

# Reboot the device to load NVIDIA drivers
# In background to avoid breaking the SSH connection prematurely
echo "Rebooting the device"
ssh "$DEVICE_USER"@"$DEVICE_IP" "(sleep 3 && sudo reboot) &"

# Wait for shutdown to happen
sleep 10

# Wait for reboot
wait-for-ssh --allow-degraded --times 15 --delay 60 || exit 1
echo "::endgroup::"
