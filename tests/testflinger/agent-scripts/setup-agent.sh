#!/bin/bash -eu

echo "::group::Installing hwcert tools"
curl -Ls -o install_tools.sh https://raw.githubusercontent.com/canonical/hwcert-jenkins-tools/main/install_tools.sh
# install the scriptlets and other tools on the agent and the device, as necessary
export TOOLS_PATH=tools
source install_tools.sh $TOOLS_PATH
[ ! "$?" -eq 0 ] && echo "::error::Failed to run tools installer" && exit 1
echo "::endgroup::"

echo "::group::Installing agent dependencies"
sudo apt-get install --yes bc
#sudo snap install jq # Can't install snaps on agent, but it is already available.
echo "::endgroup::"
