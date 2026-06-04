#!/bin/bash

set -euo pipefail

# Configuration variables
CLI_TOOL="${CLI_TOOL:-gh}"

# Global variables
model_name=""
snap_name=""
repo_name=""
repo_owner=""
team_slug=""
visibility=""
ruleset_file=""
modify_existing_repo=false
dry_run=false
assume_yes=false
debug=false

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
    local response=""
    local exit_code=0

    if [[ "$dry_run" == true ]]; then
        print_cmd "$CLI_TOOL" api --method "$method" "$endpoint" --input -
        printf "%s\n" "$payload"
    else
        # Keep successful calls quiet, but print API output when a call fails.
        response="$(printf "%s\n" "$payload" | "$CLI_TOOL" api --method "$method" "$endpoint" --input - 2>&1)" || exit_code=$?
        if [[ "$exit_code" -ne 0 || "$debug" == true ]]; then
            if [[ -n "$response" ]]; then
                printf "%s\n" "$response" >&2
            fi
            return "$exit_code"
        fi
    fi
}

ask_yes_no() {
    if [[ "$assume_yes" == true ]]; then
        return 0
    fi

    read -r -p "$1 [y/N] " response
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
Usage: $0 --model <model_name> --snap <snap_name> --visibility <public|private|internal> --owner <owner> [options]

Create and configure a new inference snap repository.

Required arguments:
  --model <model_name>      Model name used in the repository description.
  --snap <snap_name>        Snap store name. Must be lowercase and contain only
                            letters, digits, and single dashes.
  --visibility <visibility> Repository visibility: public, private, or internal.
  --owner <owner>           Repository owner (user or organization).

Optional arguments:
  --add-team <team_slug>    Add a team with direct access (admin permissions) to the repository.
  --repo <repo_name>        Repository name. Defaults to <snap_name>-snap.
  --add-ruleset <file>      Add branch rules from a ruleset file.
  --modify-existing-repo    Skip repository creation and apply settings to an existing 
                            repository. If used, --visibility is ignored.
  --assume-yes              Skip confirmation prompts.
  --debug                   Show full GitHub API responses.
  --dry-run                 Print GitHub commands without executing them.
  -h, --help                    Show this help message and exit.

Environment overrides:
  CLI_TOOL                  Command-line tool for GitHub interactions (default: gh).

Examples:
  $0 --model model5 --snap model5 --visibility public --owner canonical
  $0 --model "Model 3.5 Flash" \\
    --snap "model3-5-flash" \\
    --owner canonical \\
    --repo custom-repo \\
    --visibility private \\
    --add-ruleset data/repository/default_ruleset.json
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

validate_owner_name() {
    local value="$1"

    # GitHub user/org names are 1-39 chars, alphanumeric or single hyphens, and cannot start/end with '-'.
    if [[ ! "$value" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?$ ]]; then
        fail "invalid owner '$value'. Expected 1-39 characters using letters, digits, and single dashes; cannot start or end with a dash."
    fi

    if [[ "$value" == *--* ]]; then
        fail "invalid owner '$value'. Consecutive dashes are not allowed in GitHub owner names."
    fi
}

validate_repo_name() {
    local value="$1"

    # Repository names cannot contain spaces or '/'. Keep this strict to avoid malformed API calls.
    if [[ ! "$value" =~ ^[A-Za-z0-9._-]+$ ]]; then
        fail "invalid repo name '$value'. Expected letters, digits, dot, underscore, or dash only."
    fi

    if [[ "$value" == *.git ]]; then
        fail "invalid repo name '$value'. Do not include the '.git' suffix."
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
            --owner)
                [[ $# -ge 2 ]] || fail "--owner requires a value"
                repo_owner="$2"
                shift 2
                ;;
            --repo)
                [[ $# -ge 2 ]] || fail "--repo requires a value"
                repo_name="$2"
                shift 2
                ;;
            --add-team)
                [[ $# -ge 2 ]] || fail "--add-team requires a value"
                team_slug="$2"
                shift 2
                ;;
            --add-ruleset)
                [[ $# -ge 2 ]] || fail "--add-ruleset requires a value"
                ruleset_file="$2"
                shift 2
                ;;
            --visibility)
                [[ $# -ge 2 ]] || fail "--visibility requires a value"
                visibility="$2"
                shift 2
                ;;
            --modify-existing-repo)
                modify_existing_repo=true
                shift
                ;;
            --assume-yes)
                assume_yes=true
                shift
                ;;
            --debug)
                debug=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -h|--help)
                print_help
                exit 0
                ;;
            *)
                fail "unknown argument '$1'"
                ;;
        esac
    done
}

validate_team_slug() {
    [[ -n "$team_slug" ]] || return 0

    if [[ "$dry_run" == true ]]; then
        echo "Dry run: skipping team existence check for @${repo_owner}/${team_slug}."
        return 0
    fi

    echo "Validating team @${repo_owner}/${team_slug} exists..."
    if ! "$CLI_TOOL" api "/orgs/${repo_owner}/teams/${team_slug}" >/dev/null 2>&1; then
        fail "team '@${repo_owner}/${team_slug}' not found or inaccessible."
    fi
}

validate_inputs() {
    [[ -n "$model_name" ]] || fail "--model is required and cannot be empty"
    [[ -n "$snap_name" ]] || fail "--snap is required and cannot be empty"
    validate_snap_name "$snap_name"

    [[ -n "$repo_owner" ]] || fail "--owner is required and cannot be empty"
    validate_owner_name "$repo_owner"

    if [[ -n "$repo_name" ]]; then
        validate_repo_name "$repo_name"
    fi

    if [[ "$modify_existing_repo" == false ]]; then
        # Only validate visibility if we're creating a new repo.
        [[ -n "$visibility" ]] || fail "--visibility is required and cannot be empty"
        case "$visibility" in
            public|private|internal)
                ;;
            *)
                fail "invalid visibility '$visibility'. Expected 'public', 'private', or 'internal'."
                ;;
        esac
    fi

    # Ensure required files exist
    if [[ -n "$ruleset_file" && ! -f "$ruleset_file" ]]; then
        fail "Ruleset file '$ruleset_file' not found."
    fi
}

ensure_repo_exists() {
    if [[ "$modify_existing_repo" == true ]]; then
        # Validate repo existence
        echo "Verifying repository ${repo_owner}/${repo_name} exists for modification..."
        # Use a silent API probe instead of `gh repo view` to avoid pager/full-screen output.
        if ! gh_api_json GET "/repos/${repo_owner}/${repo_name}" ""; then
            fail "Repository '${repo_owner}/${repo_name}' not found or inaccessible. Cannot modify non-existing repository."
        fi
    else
        # Create repo
        echo "Creating repository ${repo_owner}/${repo_name}..."
        gh_cmd repo create "${repo_owner}/${repo_name}" "--${visibility}"
    fi
}

setup_repository_settings() {
    # Add topic
    echo "Setting repository topic..."
    gh_api_json PUT "/repos/${repo_owner}/${repo_name}/topics" "$(cat <<EOF
{
    "names": [
        "inference-snap"
    ]
}
EOF
)"

    # Customize settings
    echo "Applying repository-level settings after creation..."
    gh_api_json PATCH "/repos/${repo_owner}/${repo_name}" "$(cat <<EOF
{
    "description": "Local inference with ${model_name}",
    "homepage": "https://snapcraft.io/${snap_name}",
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
    if [[ -z "$team_slug" ]]; then
        echo "Skipping team permissions setup: no team specified."
        return 0
    fi

    # Add REPOSITORY_OWNER/team_slug (e.g. "@canonical/industrial") team with direct access (admin permissions)
    # Doing this with "--team" during repo creation isn't reliable, see here: https://github.com/cli/cli/discussions/6906

    # API specification: https://docs.github.com/en/rest/teams/teams?apiVersion=2026-03-10#add-or-update-team-repository-permissions
    # Permission levels: https://docs.github.com/en/organizations/managing-user-access-to-your-organizations-repositories/managing-repository-roles/repository-roles-for-an-organization#permission-levels-for-repositories-owned-by-an-organization

    echo "Granting team permissions to @${repo_owner}/${team_slug}..."
    gh_api_json PUT "/orgs/${repo_owner}/teams/${team_slug}/repos/${repo_owner}/${repo_name}" "{\"permission\": \"admin\"}"
}

add_branch_rules() {
    if [[ -z "$ruleset_file" ]]; then
        echo "Skipping branch rules setup: no ruleset file provided."
        return 0
    fi

    echo "Creating branch ruleset for the default branch..."
    gh_api_json POST "/repos/${repo_owner}/${repo_name}/rulesets" "$(cat "$ruleset_file")"
}

add_workflow_trigger_labels() {
    echo "Creating workflow trigger labels..."

    gh_cmd label create --force trigger-build --repo "${repo_owner}/${repo_name}" --color EEEEEE --description "Trigger build pipeline and publish snap"
    gh_cmd label create --force trigger-tests --repo "${repo_owner}/${repo_name}" --color 666666 --description "Trigger test pipeline on last build, if not present triggers also build"
}

add_github_action_variables() {
    echo "Creating GitHub Actions variables..."

    set_github_action_variable() {
        local name="$1"
        local value="$2"

        # Upsert behavior: update when the variable exists, otherwise create it.
        if ! gh_api_json PATCH "/repos/${repo_owner}/${repo_name}/actions/variables/${name}" "$(cat <<EOF
{
    "name": "${name}",
    "value": "${value}"
}
EOF
)"; then
            gh_api_json POST "/repos/${repo_owner}/${repo_name}/actions/variables" "$(cat <<EOF
{
    "name": "${name}",
    "value": "${value}"
}
EOF
)"
        fi
    }

    set_github_action_variable "PR_BUILD_TRIGGER_LABEL" "trigger-build"
    set_github_action_variable "PR_TEST_TRIGGER_LABEL" "trigger-tests"
}

main() {
    parse_args "$@"

    # Infer repo name if not provided
    if [[ -z "$repo_name" ]]; then
        repo_name="${snap_name}-snap"
    fi

    validate_inputs

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

    validate_team_slug

    # Summary
    echo ""
    echo "Repository will be set-up with the following values:"
    echo "  - Model name: $model_name"
    echo "  - Repository: $repo_owner/$repo_name"
    echo "  - Snap name: $snap_name"
    echo "  - Repository visibility: $([[ "$modify_existing_repo" == true ]] && echo "unchanged" || echo "$visibility")"
    echo "  - Team with admin access: ${team_slug:-none}"
    echo "  - Branch ruleset file: ${ruleset_file:-none}"
    echo ""
    echo "The repository will be available at https://github.com/$repo_owner/$repo_name"
    echo ""

    if [[ "$modify_existing_repo" == true ]]; then
        echo "WARNING: --modify-existing-repo is enabled, this script will change settings to an existing repository. Repository visibility will be left unchanged."
        echo ""
    fi

    # Confirmation
    if [[ "$assume_yes" == true ]]; then
        echo "Assuming yes: skipping confirmation prompts."
    elif ! ask_yes_no "Do you want to proceed with these settings?"; then
        echo "Aborting."
        exit 0
    fi

    # Execution
    ensure_repo_exists
    setup_repository_settings
    add_workflow_trigger_labels
    add_github_action_variables
    add_team_permissions
    add_branch_rules

    # Completion message
    echo "Repository setup complete!"
    echo "Access it here: https://github.com/$repo_owner/$repo_name"
}

main "$@"
