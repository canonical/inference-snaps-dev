#!/bin/bash -eux

# Local or testflinger machine ssh details
export DEVICE_IP="localhost"
export DEVICE_USER=$USER

# Snap to test
export SNAP_NAME="gemma3"
export SNAP_CHANNEL="latest/stable"

# Drivers and other prerequisites to set up before installation of the snap
export INSTALL_NVIDIA_DRIVER_VERSION="580-server"
export INSTALL_INTEL_NPU_DRIVER=""
export SNAP_CONNECTIONS=""

# Autoselection is always performed during snap installation
export EXPECTED_ENGINE=""
export SELECT_ENGINE="cpu"

# Test chat prompt and check TPS
export TEST_CHAT_TPS="true"
export EXPECTED_TPS=0

# Test image prompt
export TEST_IMAGE_PROMPT="true"
