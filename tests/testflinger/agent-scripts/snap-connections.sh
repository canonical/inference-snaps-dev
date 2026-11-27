#!/bin/bash -eu

if [ -n "$SNAP_CONNECTIONS" ]; then
  echo "::group::Connecting snap interfaces"
  # Temporarily set IFS to a comma just for the 'read' command
  # -r prevents backslash escaping
  # -a assigns the result to an array named 'my_array'
  IFS=',' read -r -a my_array <<< "$SNAP_CONNECTIONS"

  # Iterate over the new array safely
  for connection in "${my_array[@]}"; do
      echo "Processing: $connection"
      _run sudo snap connect $SNAP_NAME:$connection
  done
  wait-for-snap-changes
  echo "::endgroup::"
fi
echo "::group::Checking snap connections"
_run sudo snap connections "$SNAP_NAME"
echo "::endgroup::"
