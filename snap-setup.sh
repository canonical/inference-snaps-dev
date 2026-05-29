#!/bin/bash

set -euo pipefail

CLI_TOOL="${CLI_TOOL:-snapcraft}"

snap_name=""
visibility=""
collaborator_emails_csv=""
assume_yes=false
dry_run=false

print_cmd() {
	printf "+ "
	printf "%q " "$@"
	printf "\n"
}

sc_cmd() {
	if [[ "$dry_run" == true ]]; then
		print_cmd "$CLI_TOOL" "$@"
	else
		"$CLI_TOOL" "$@"
	fi
}

fail() {
	echo "Error: $1" >&2
	exit 1
}

validate_snap_name() {
	local value="$1"

	if [[ ! "$value" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
		fail "invalid snap name '$value'. Expected lowercase letters, digits, and single dashes only."
	fi
}

usage() {
	cat <<EOF
Usage: $0 --snap <snap_name> --visibility <value> [options]

Register a snap in the store.

Required arguments:
  --snap <snap_name>            Snap name to register.
  --visibility <value>          Snap visibility: public or private

Optional arguments:
  --collaborators <csv>         Comma-separated collaborator email list, e.g. "a@example.com,b@example.com".
  --assume-yes                  Skip confirmation prompt.
  --dry-run                     Print commands without executing them.
  -h, --help                    Show this help message and exit.

Environment overrides:
  CLI_TOOL                      Path to the CLI binary to use (default: snapcraft).

Examples:
  $0 --snap deepseek-r1 --visibility private --collaborators dev@example.com
  $0 --snap deepseek-r1 --visibility public --collaborators "a@example.com,b@example.com"
EOF
}

ask_yes_no() {
	if [[ "$assume_yes" == true ]]; then
		return 0
	fi

	read -r -p "$1 (y/N): " response
	case "$response" in
		[yY][eE][sS]|[yY])
			return 0
			;;
		*)
			return 1
			;;
	esac
}

parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--snap)
				[[ $# -ge 2 ]] || fail "--snap requires a value"
				snap_name="$2"
				shift 2
				;;
			--visibility)
				[[ $# -ge 2 ]] || fail "--visibility requires a value"
				visibility="$2"
				shift 2
				;;
			--collaborators)
				[[ $# -ge 2 ]] || fail "--collaborators requires a value"
                if [[ -z "$collaborator_emails_csv" ]]; then
                    # Init
                    collaborator_emails_csv="$2"
                else
                    # Append
                    collaborator_emails_csv="$collaborator_emails_csv,$2"
                fi
				shift 2
				;;
			--assume-yes)
				assume_yes=true
				shift
				;;
			--dry-run)
				dry_run=true
				shift
				;;
			-h|--help)
				usage
				exit 0
				;;
			*)
				fail "unknown argument '$1'"
				;;
		esac
	done
}

validate_inputs() {
	[[ -n "$snap_name" ]] || fail "--snap is required"
    [[ -n "$visibility" ]] || fail "--visibility is required"

	validate_snap_name "$snap_name"

	case "$visibility" in
		public|private)
			;;
		*)
			fail "invalid visibility '$visibility'. Expected 'public' or 'private'."
			;;
	esac
}

ensure_snapcraft_available() {
	if ! command -v "$CLI_TOOL" >/dev/null 2>&1; then
		fail "'$CLI_TOOL' was not found. Install snapcraft by running: 'sudo snap install snapcraft --classic'"
	fi
}

ensure_snapcraft_logged_in() {
	if [[ "$dry_run" == true ]]; then
		echo "Dry run: skipping login status check."
		return 0
	fi

	if ! "$CLI_TOOL" whoami >/dev/null 2>&1; then
		fail "Snapcraft is not logged in. Run '$CLI_TOOL login' and retry."
	fi
}

register_snap() {
    local register_args=(register "$snap_name" --yes)
    
    if [[ "$visibility" == "private" ]]; then
        register_args+=("--private")
    fi

	echo "Registering snap '$snap_name' with visibility '$visibility'..."
	sc_cmd "${register_args[@]}"
}

main() {
	parse_args "$@"
	validate_inputs

	ensure_snapcraft_available
	ensure_snapcraft_logged_in

	echo ""
	echo "The following setup will be applied:"
	echo "  - Snap name: $snap_name"
	echo "  - Visibility: $visibility"
	echo ""

	if ! ask_yes_no "> Continue"; then
		echo "Aborting."
		exit 0
	fi

	register_snap

	echo "Snap setup complete for '$snap_name'."

    if [[ -n "$collaborator_emails_csv" ]]; then
        echo "Please visit the snapcraft dashboard to add collaborators: https://dashboard.snapcraft.io/snaps/$snap_name/collaboration/"
        echo ""
        echo "Collaborators:"
        echo "  $collaborator_emails_csv"
        echo ""
    fi
}

main "$@"


