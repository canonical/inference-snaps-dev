#!/bin/bash -eu

git_branch=$(git rev-parse --abbrev-ref HEAD)
default_channel="latest/edge/$git_branch"

channel=${1-$default_channel}

snap_file="$(ls *.snap)"

if [ "$(echo "$snap_file" | wc -l)" -ne 1 ]; then
    echo -e "Error: expected 1 snap file, found multiple: \n$snap_file"
    exit 1
fi

snap_size=$(du -h "$snap_file" | cut -f1)
echo -e "Snap file:\n\t$snap_file $snap_size"

# Build components argument list
component_args=()
component_list=()
echo "Snap components:"
for comp_file in *.comp; do
    comp_size=$(du -h "$comp_file" | cut -f1)

    # Component file name patterns:
    # <snap_name>+<comp_name>_<comp_version>.comp
    # <snap_name>+<comp_name>.comp
    comp_name=$(echo "$comp_file" | 
        cut -d'+' -f2 | # drop snap name
        cut -d'.' -f1 | # drop file extension
        cut -d'_' -f1) # split by _, take 1st part

    echo -e "\t$comp_file $comp_size"
    
    # Check for duplicate components
    for existing_comp in "${component_list[@]}"; do
        if [[ "$existing_comp" == "$comp_name" ]]; then
            echo "Error: more than one component is named '$comp_name'"
            exit 1
        fi
    done
    component_list+=("$comp_name")

    component_args+=(--component "$comp_name=$comp_file")
done

echo -e "Channel:\n\t$channel"

echo -ne "\nType Y to start the upload: "
read confirmation
if [[ "$confirmation" != "y" && "$confirmation" != "Y" ]]; then
    exit 1
fi

set -x
snapcraft upload "$snap_file" "${component_args[@]}" --release="$channel"
