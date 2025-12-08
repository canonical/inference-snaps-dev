#!/bin/bash -eu

function check_file() {
    local file=$1
    if [ ! -f "$file" ]; then
        echo "Error: file not found: $file"
        exit 1
    fi
}

channel=${1:-}
if [ -z "$channel" ]; then
    echo "Channel not set."
    echo "Usage: $0 <channel>"
    exit 1
fi

snap_file="$(ls *.snap)"
check_file "$snap_file"
snap_size=$(du -h "$snap_file" | cut -f1)
echo -e "Snap file:\n\t$snap_file $snap_size"

# Build components argument list
component_args=()
echo "Snap components:"
for comp_file in *.comp; do
    check_file "$comp_file"
    comp_size=$(du -h "$comp_file" | cut -f1)

    # Component file name patterns:
    # <snap_name>+<comp_name>_<comp_version>.comp
    # <snap_name>+<comp_name>.comp
    comp_name=$(echo "$comp_file" | 
        cut -d'+' -f2 | # drop snap name
        cut -d'.' -f1 | # drop file extension
        cut -d'_' -f1) # split by _, take 1st part

    echo -e "\t$comp_file $comp_size"

    component_args+=(--component "$comp_name=$comp_file")
done

echo -e "Channel:\n\t$channel"

echo -e "\nUploading snap..."
set -x
snapcraft upload "$snap_file" "${component_args[@]}" --release="$channel"
