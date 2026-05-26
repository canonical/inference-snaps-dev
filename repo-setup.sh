#!/bin/bash

set -euo pipefail

# Configuration variables
REPOSITORY_OWNER="canonical"
TEAM_NAME="industrial"
CLI_TOOL="gh"
DRY_RUN=false

print_cmd() {
    printf "+ "
    printf "%q " "$@"
    printf "\n"
}

gh_cmd() {
    if [[ "$DRY_RUN" == true ]]; then
        print_cmd "$CLI_TOOL" "$@"
    else
        "$CLI_TOOL" "$@"
    fi
}

gh_api_json() {
    local method="$1"
    local endpoint="$2"
    local payload="$3"

    if [[ "$DRY_RUN" == true ]]; then
        print_cmd "$CLI_TOOL" api --method "$method" "$endpoint" --input -
        printf "%s\n" "$payload"
    else
        printf "%s\n" "$payload" | "$CLI_TOOL" api --method "$method" "$endpoint" --input -
    fi
}

ask_yes_no() {
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

create_repo() {
#   - Create repository (public or private, as desired)
#   - Disable Wiki, Issues and Projects
#   - Disallow merge commits and rebase merges, but allow squash merges
#   - Enable "Always suggest updating pull request branches "
#   - Enable "Allow auto-merge"
#   - Enable "Automatically delete head branches"
#   - Enable main branch protection rules (require pull request reviews before merging, require status checks to pass before merging, require branches to be up to date before merging)

    local visibility_flag="--public"
    if [[ "$private" == true ]]; then
        visibility_flag="--private"
    fi

    echo "Creating repository ${REPOSITORY_OWNER}/${repo_name}..."
    gh_cmd repo create "${REPOSITORY_OWNER}/${repo_name}" "$visibility_flag"

    # Apply repository-level settings after creation.
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
    #  - Add REPOSITORY_OWNER/TEAM_NAME (e.g. "@canonical/industrial") team with direct access (admin permissions)
    echo "Granting team permissions to @${REPOSITORY_OWNER}/${TEAM_NAME}..."
    gh_api_json PUT "/orgs/${REPOSITORY_OWNER}/teams/${TEAM_NAME}/repos/${REPOSITORY_OWNER}/${repo_name}" "$(cat <<EOF
{
    "permission": "admin"
}
EOF
)"
}

add_branch_rules() {
#   - Create ruleset for main branch:
#       - Bypass list: Repository Admin
#       - Target branch: default (main)
#       - Only restrict deletions
#       - Require signed commits
#       - Require a pull request before merging
#       - Block force pushes
    echo "Creating branch ruleset for the default branch..."
    gh_api_json POST "/repos/${REPOSITORY_OWNER}/${repo_name}/rulesets" "$(cat <<EOF
{
    "name": "main-branch-protection",
    "target": "branch",
    "enforcement": "active",
    "bypass_actors": [
        {
            "actor_id": 5,
            "actor_type": "RepositoryRole",
            "bypass_mode": "pull_request"
        }
    ],
    "conditions": {
        "ref_name": {
            "include": [
                "~DEFAULT_BRANCH"
            ],
            "exclude": []
        }
    },
    "rules": [
        {
            "type": "deletion"
        },
        {
            "type": "non_fast_forward"
        },
        {
            "type": "required_signatures"
        },
        {
            "type": "pull_request",
            "parameters": {
                "required_approving_review_count": 1,
                "dismiss_stale_reviews_on_push": false,
                "required_reviewers": [],
                "require_code_owner_review": false,
                "require_last_push_approval": false,
                "required_review_thread_resolution": false,
                "allowed_merge_methods": [
                    "squash"
                ]
            }
        }
    ]
}
EOF
)"
}

add_website_and_description() {
#   - Add description: "Local inference with ${model_name}"
#   - Add website: "https://snapcraft.io/${snap_name}"
#   - Add Topic: "inference-snap"
    echo "Setting repository description, website, and topic..."
    gh_api_json PATCH "/repos/${REPOSITORY_OWNER}/${repo_name}" "$(cat <<EOF
{
    "description": "Local inference with ${model_name}",
    "homepage": "https://snapcraft.io/${snap_name}"
}
EOF
)"

    gh_api_json PUT "/repos/${REPOSITORY_OWNER}/${repo_name}/topics" "$(cat <<EOF
{
    "names": [
        "inference-snap"
    ]
}
EOF
)"
}

add_workflow_trigger_labels() {
#   - Add label "trigger-build" with description "Trigger build pipeline and publish snap"
#   - Add label "trigger-tests" with description "Trigger test pipeline on last build, if not present triggers also build"
    echo "Creating workflow trigger labels..."
    gh_cmd label create trigger-build --repo "${REPOSITORY_OWNER}/${repo_name}" --color 78af54 --description "Trigger build pipeline and publish snap" --force
    gh_cmd label create trigger-tests --repo "${REPOSITORY_OWNER}/${repo_name}" --color 9a1f77 --description "Trigger test pipeline on last build, if not present triggers also build" --force
}

print_help() {
    echo "Usage: $0"
    echo ""
    echo "This script will guide you through the creation and setup of a new repository for an inference snap."
    echo "It will ask you for the necessary information and then create the repository with the appropriate settings and permissions."
    echo ""
    echo "You can use '--dry-run' option to see what actions would be taken without actually performing them."
    echo ""
}

main() {
    # Read parameters (--help or --dry-run)
    for arg in "$@"; do
        case "$arg" in
            --dry-run)
                DRY_RUN=true
                ;;
            --help)
                print_help
                exit 0
                ;;
            *)
                echo "Error: unknown argument '$arg'"
                print_help
                exit 1
                ;;
        esac
    done

    if [[ "$DRY_RUN" == true ]]; then
        echo "Dry run mode: no changes will be made to GitHub."
    fi

    echo "This script will guide you into the creation and setup of a new repository for an inference snap."
    echo ""

    # Check if GitHub CLI is installed
    if ! command -v "$CLI_TOOL" &> /dev/null; then
        echo "Error: GitHub CLI ($CLI_TOOL) is required, but not installed. You can install it from https://cli.github.com/."
        exit 1
    fi

    if [[ "$DRY_RUN" == false ]] && ! "$CLI_TOOL" auth status >/dev/null 2>&1; then
        echo "Error: GitHub CLI is not authenticated. Run 'gh auth login' first."
        exit 1
    fi

    # Data input: model name
    read -p "> Enter the AI model name (e.g. 'model5'): " model_name
    if [[ -z "$model_name" ]]; then
        echo "Error: model name cannot be empty."
        exit 1
    fi

    # Data input: snap store name
    read -p "> Enter the snap store name (default: '${model_name}'): " snap_name
    if [[ -z "$snap_name" ]]; then
        snap_name="$model_name"
    fi

    # Data input: repository name
    read -p "> Enter a name for the new repository (default: '${model_name}-snap'): " repo_name
    if [[ -z "$repo_name" ]]; then
        repo_name="${model_name}-snap"
    fi

    # Data input: private or public repository
    if ask_yes_no "> Should the repository be private?"; then
        private=true
    else
        private=false
    fi

    # Summary and confirmation
    echo ""
    echo "Repository will be created with the following settings:"
    echo "  - Model name: $model_name"
    echo "  - Repository name: $repo_name"
    echo "  - Snap name: $snap_name"
    echo "  - Repository visibility: $([[ "$private" == true ]] && echo "private" || echo "public")"
    echo ""

    if ! ask_yes_no "> Do you want to proceed with these settings?"; then
        echo "Aborting."
        exit 0
    fi

    # Execution
    create_repo
    add_team_permissions
    add_branch_rules
    add_website_and_description
    add_workflow_trigger_labels

    # Completion message
    echo "Repository setup complete!"
    echo "Access it here: https://www.github.com/$REPOSITORY_OWNER/$repo_name"
}

main "$@"
