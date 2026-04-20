#!/bin/bash -eu

help() {
  echo "Usage:" >&2
  echo "  $0 [--wipe] [--help] [snapcraft-pack-options...]" >&2
  echo "" >&2
  echo "Options:" >&2
  echo "  -h, --help  Show this help message" >&2
  echo "  --wipe    Remove existing .snap and .comp before packing" >&2
}

wipe=false
snapcraft_args=()

while (($#)); do
  case "$1" in
    -h|--help)
      help
      exit 0
      ;;
    --wipe)
      wipe=true
      ;;
    --)
      shift
      snapcraft_args+=("$@")
      break
      ;;
    *)
      help
      exit 1
      ;;
  esac
  shift
done

if [[ "$wipe" == true ]]; then
    rm -fv *.snap *.comp
fi

snapcraft -v pack "${snapcraft_args[@]}"
