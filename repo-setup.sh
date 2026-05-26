#!/bin/bash

set -euo pipefail

# Configuration variables
RULESET_FILE=${RULESET_FILE:-"data/repository/default_ruleset.json"}
REPOSITORY_OWNER="${REPOSITORY_OWNER:-canonical}"
TEAM_NAME="${TEAM_NAME:-industrial}"
CLI_TOOL="${CLI_TOOL:-gh}"

# Global variables
model_name=""
snap_name=""
repo_name=""
visibility=""
dry_run=false
assume_yes=false

print_cmd() {
    printf "+ "
    printf "%q " "$@"
    printf "\n"
}

gh_cmd() {
    if [[ "$dry_run" == true ]]; then
        print_cmd "$CLI_TOOL" "$@"
    else
        "$CLI_TOOL" "$@"
    fi
}

gh_api_json() {
    local method="$1"
    local endpoint="$2"
    local payload="$3"

    if [[ "$dry_run" == true ]]; then
        print_cmd "$CLI_TOOL" api --method "$method" "$endpoint" --input -
        printf "%s\n" "$payload"
    else
        printf "%s\n" "$payload" | "$CLI_TOOL" api --method "$method" "$endpoint" --input -
    fi
}

ask_yes_no() {
    if [[ "$assume_yes" == true ]]; then
        return 0
    fi

    read -p "$1 (y/N): " response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

print_help() {
    cat <<EOF
Usage: $0 --model <model_name> --snap <snap_name> --visibility <public|private|internal> [options]

Create and configure a new inference snap repository under ${REPOSITORY_OWNER}.

Required arguments:
  --model <model_name>      Model name used in the repository description.
  --snap <snap_name>        Snap store name. Must be lowercase and contain only
                            letters, digits, and single dashes.
  --visibility <visibility> Repository visibility: public, private, or internal.

Optional arguments:
  --repo <repo_name>        Repository name. Defaults to <snap_name>-snap.
  --assume-yes              Skip confirmation prompts.
  --dry-run                 Print GitHub commands without executing them.
  --help                    Show this help message and exit.

Environment overrides:
  REPOSITORY_OWNER, TEAM_NAME, CLI_TOOL, RULESET_FILE

Examples:
  $0 --model model5 --snap model5 --visibility public
  $0 --model "Model 3.5 Flash" --snap "model3-5-flash" --repo custom-repo --visibility private --assume-yes
EOF
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

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --model)
                [[ $# -ge 2 ]] || fail "--model requires a value"
                model_name="$2"
                shift 2
                ;;
            --snap)
                [[ $# -ge 2 ]] || fail "--snap requires a value"
                snap_name="$2"
                shift 2
                ;;
            --repo)
                [[ $# -ge 2 ]] || fail "--repo requires a value"
                repo_name="$2"
                shift 2
                ;;
            --visibility)
                [[ $# -ge 2 ]] || fail "--visibility requires a value"
                visibility="$2"
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
            --help)
                print_help
                exit 0
                ;;
            *)
                fail "unknown argument '$1'"
                ;;
        esac
    done
}

validate_inputs() {
    [[ -n "$model_name" ]] || fail "--model is required and cannot be empty"
    [[ -n "$snap_name" ]] || fail "--snap is required and cannot be empty"
    [[ -n "$visibility" ]] || fail "--visibility is required and cannot be empty"

    case "$visibility" in
        public|private|internal)
            ;;
        *)
            fail "invalid visibility '$visibility'. Expected 'public', 'private', or 'internal'."
            ;;
    esac

    validate_snap_name "$snap_name"

    if [[ -z "$repo_name" ]]; then
        repo_name="${snap_name}-snap"
    fi
}

create_repo() {
    echo "Creating repository ${REPOSITORY_OWNER}/${repo_name}..."
    
    repo_description="Local inference with ${model_name}"
    repo_homepage="https://snapcraft.io/${snap_name}"

    # Create repo
    gh_cmd repo create "${REPOSITORY_OWNER}/${repo_name}" \
        "--${visibility}" \
        --description "$repo_description" \
        --homepage "$repo_homepage"

    # Add topic
    echo "Setting repository topic..."
    gh_api_json PUT "/repos/${REPOSITORY_OWNER}/${repo_name}/topics" "$(cat <<EOF
{
    "names": [
        "inference-snap"
    ]
}
EOF
)"
    # Customize settings after creation, since some settings (e.g. squash merge) can't be set during creation
    echo "Applying repository-level settings after creation..."
    gh_api_json PATCH "/repos/${REPOSITORY_OWNER}/${repo_name}" "$(cat <<EOF
{
    "has_wiki": false,
    "has_issues": false,
    "has_projects": false,
    "allow_merge_commit": false,
    "allow_rebase_merge": false,
    "allow_squash_merge": true,
    "allow_update_branch": true,
    "allow_auto_merge": true,
    "delete_branch_on_merge": true
}
EOF
)"
}

add_team_permissions() {
    # Add REPOSITORY_OWNER/TEAM_NAME (e.g. "@canonical/industrial") team with direct access (admin permissions)
    # Doing this with "--team" during repo creation isn't reliable, see here: https://github.com/cli/cli/discussions/6906

    echo "Granting team permissions to @${REPOSITORY_OWNER}/${TEAM_NAME}..."
    gh_api_json PUT "/orgs/${REPOSITORY_OWNER}/teams/${TEAM_NAME}/repos/${REPOSITORY_OWNER}/${repo_name}" "{\"permission\": \"admin\"}"
}

add_branch_rules() {
    echo "Creating branch ruleset for the default branch..."
    gh_api_json POST "/repos/${REPOSITORY_OWNER}/${repo_name}/rulesets" "$(cat "$RULESET_FILE")"
}

add_workflow_trigger_labels() {
    echo "Creating workflow trigger labels..."

    gh_cmd label create --force trigger-build --repo "${REPOSITORY_OWNER}/${repo_name}" --color 78AF54 --description "Trigger build pipeline and publish snap"
    gh_cmd label create --force trigger-tests --repo "${REPOSITORY_OWNER}/${repo_name}" --color 9A1F77 --description "Trigger test pipeline on last build, if not present triggers also build"
}

main() {
    # Args parsing and validation
    parse_args "$@"
    validate_inputs

    # Ensure required files exist
    if [[ ! -f "$RULESET_FILE" ]]; then
        fail "Ruleset file '$RULESET_FILE' not found."
    fi


    # Check if GitHub CLI is installed
    if ! command -v "$CLI_TOOL" &> /dev/null; then
        fail "GitHub CLI ($CLI_TOOL) is required, but not installed. You can install it from https://cli.github.com/."
    fi

    if [[ "$dry_run" == true ]]; then
        echo "Dry run mode: no changes will be made to GitHub."
    else 
        # Check if GitHub CLI is authenticated
        if ! gh_cmd auth status >/dev/null 2>&1; then
            fail "GitHub CLI is not authenticated. Run 'gh auth login' first."
        fi
    fi

    # Summary and confirmation
    echo ""
    echo "Repository will be created with the following settings:"
    echo "  - Model name: $model_name"
    echo "  - Repository name: $repo_name"
    echo "  - Snap name: $snap_name"
    echo "  - Repository visibility: $visibility"
    echo ""
    echo "Once created, the repository will be available at https://www.github.com/$REPOSITORY_OWNER/$repo_name"
    echo ""

    # Confirmation
    if [[ "$assume_yes" == true ]]; then
        echo "Assuming yes: skipping confirmation prompts."
    elif ! ask_yes_no "> Do you want to proceed with these settings?"; then
        echo "Aborting."
        exit 0
    fi

    # Execution
    create_repo
    add_team_permissions
    add_branch_rules
    add_workflow_trigger_labels

    # Completion message
    echo "Repository setup complete!"
    echo "Access it here: https://www.github.com/$REPOSITORY_OWNER/$repo_name"
}

main "$@"
