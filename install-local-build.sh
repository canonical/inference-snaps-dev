#!/bin/bash -e

# load snapcraft.yaml into variable, explode to evaluate aliases
snapcraft_yaml=$(yq '. | explode(.)' snap/snapcraft.yaml)

snap_name=$(echo "$snapcraft_yaml" | yq '.name')

architecture=$(dpkg --print-architecture)

engine=$1
op=$2

if [[ -z "$engine" ]]; then
    echo "Error: Engine name is required."
    echo "Usage: $0 <engine> [clean]"
    exit 1
fi

if [[ "$op" == "clean" ]]; then
    sudo snap remove "$snap_name"
fi

# Validate engine name
engine_file=./engines/$engine/engine.yaml
if [[ ! -f "$engine_file" ]]; then
    echo "Unknown engine: $engine"
    exit 1
fi


if [[ "$(yq --version)" != *v4* ]]; then
    echo "Please install yq v4."
    exit 1
fi

# Validate engine syntax
yq engines/$engine/engine.yaml > /dev/null

# Install the snap
sudo snap install --dangerous $snap_name_*_$architecture.snap

# The snaps is unable to auto-select an engine without hardware access.
# Stop since the service is going to fail without an engine
sudo snap stop "$snap_name"

# Connect interfaces
sudo snap connect $snap_name:home
sudo snap connect $snap_name:hardware-observe


# Install engine components
cat "./engines/$engine/engine.yaml" | yq .components[] | while read -r component; do
    sudo snap install --dangerous ./$snap_name+"$component"_*.comp
done

# Set engine
sudo "$snap_name" use-engine "$engine" --assume-yes

# Start service
sudo snap start "$snap_name"
