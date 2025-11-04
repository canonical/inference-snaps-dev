#!/bin/bash -e

# load snapcraft.yaml into variable, explode to evaluate aliases
snapcraft_yaml=$(yq '. | explode(.)' snap/snapcraft.yaml)

snap_name=$(echo "$snapcraft_yaml" | yq '.name')
arch=$(dpkg --print-architecture)

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

# Ensure that the working directory contains single snap and component builds
if [ $(ls *.snap 2>/dev/null | wc -l) -gt 1 ]; then
    echo "Error: found more than one .snap file in the current directory."
    exit 1
fi
cat "./engines/$engine/engine.yaml" | yq .components[] | while read -r component; do
    if [ $(ls $snap_name+$component*.comp 2>/dev/null | wc -l) -gt 1 ]; then
        echo "Error: found more than one .comp file for $component"
        exit 1
    fi
done

snap_file="$(ls ${snap_name}_*_${arch}.snap)"

if [[ "$(yq --version)" != *v4* ]]; then
    echo "Please install yq v4."
    exit 1
fi

# Validate engine syntax
yq "engines/$engine/engine.yaml" > /dev/null

# Install the snap
sudo snap install --dangerous "$snap_file"

# The snaps is unable to auto-select an engine without hardware access.
# Stop since the service is going to fail without an engine
sudo snap stop "$snap_name"

# Connect interfaces
sudo snap connect $snap_name:home
sudo snap connect $snap_name:hardware-observe


# Install engine components
cat "./engines/$engine/engine.yaml" | yq .components[] | while read -r component; do
    sudo snap install --dangerous ./$snap_name+$component*.comp
done

# Set engine
sudo "$snap_name" use-engine "$engine" --assume-yes

# Start service
sudo snap start "$snap_name"
