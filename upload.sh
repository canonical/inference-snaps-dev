#!/bin/bash -eu

channel=$1
arch=${2:-$(dpkg --print-architecture)} # if not set, take the current architecture

if [[ "$(yq --version)" != *v4* ]]; then
    echo "Please install yq v4."
    exit 1
fi

# Ensure that the working directory contains single snap and component builds
if [ $(ls *.snap 2>/dev/null | wc -l) -gt 1 ]; then
    echo "Error: found more than one .snap file in the current directory."
    exit 1
fi

# validate channel
if [[ ! "$channel" =~ ^[a-z0-9-]+/[a-z0-9-]+(/[a-z0-9-]+)?$ ]]; then
    echo "Invalid Snap channel: $channel"
    exit 1
fi

snapcraft_file="snap/snapcraft.yaml"
if [ -f "snapcraft.yaml" ]; then
    echo -e "Warning: Using top level snapcraft.yaml file!\n"
    snapcraft_file="snapcraft.yaml"
fi

# load snapcraft.yaml into variable, explode to evaluate aliases
snapcraft_yaml=$(yq '. | explode(.)' "$snapcraft_file")

snap_name=$(echo "$snapcraft_yaml" | yq '.name')
snap_file=$(ls ${snap_name}_*_${arch}.snap)
snap_size=$(du -h "$snap_file" | cut -f1)

echo -e "Snap file:\n\t$snap_file $snap_size"

# Extract components from snapcraft.yaml
components=$(echo "$snapcraft_yaml" | yq '.components | to_entries | .[].key')

# Build components argument list
component_args=()
echo "Snap components:"
for comp_name in $components; do
    # One one .comp file per component
    if [ $(ls $snap_name+$comp_name*.comp 2>/dev/null | wc -l) -gt 1 ]; then
        echo "Error: found more than one .comp file for $comp_name in the current directory."
        exit 1
    fi

    comp_file="$(ls ${snap_name}+${comp_name}*.comp)"
    comp_size=$(du -h "$comp_file" | cut -f1)
    echo -e "\t$comp_file $comp_size"

    component_args+=(--component "$comp_name=$comp_file")
done

echo -e "Channel:\n\t$channel"

echo -ne "\nType Y to start the upload: "
read confirmation
if [[ "$confirmation" == "y" || "$confirmation" == "Y" ]]; then
    snapcraft upload "$snap_file" "${component_args[@]}" --release="$channel"
fi
