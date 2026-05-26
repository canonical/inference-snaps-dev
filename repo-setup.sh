#!/bin/bash

set -e

# Configuration variables
REPOSITORY_OWNER="canonical"
TEAM_NAME="industrial"
CLI_TOOL="gh_disabled" # GitHub CLI tool # TODO: change to gh when ready, for now we disable it to avoid accidental execution while the script is being developed

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
}

add_team_permissions() {
#  - Add "@canonical/industrial" team with direct access (admin permissions)
}

add_branch_rules() {
#   - Create ruleset for main branch:
#       - Bypass list: Repository Admin
#       - Target branch: default (main)
#       - Only restrict deletions
#       - Require signed commits
#       - Require a pull request before merging
#       - Block force pushes
}

add_website_and_description() {
#   - Add description: "Local inference with ${model_name}"
#   - Add website: "https://snapcraft.io/${model_name}"
#   - Add Topic: "inference-snap"
}

add_workflow_trigger_labels() {
#   - Add label "trigger-build" with description "Trigger build pipeline and publish snap"
#   - Add label "trigger-tests" with description "Trigger test pipeline on last build, if not present triggers also build"
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
    if [[ "$1" == "--dry-run" ]]; then
        echo "Dry run mode: no changes will be made to GitHub."
        CLI_TOOL="echo $CLI_TOOL (dry run)"
    elif [[ "$1" == "--help" ]]; then
        print_help
        exit 0
    fi



    echo "This script will guide you into the creation and setup of a new repository for an inference snap."
    echo ""

    # Check if GitHub CLI is installed
    if ! command -v $CLI_TOOL &> /dev/null; then
        echo "Error: GitHub CLI ($CLI_TOOL) is required, but not installed. You can install it from https://cli.github.com/."
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
    echo "  - Repository visibility: $([[ "$private" == true ]] && echo "Private" || echo "Public")"
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

main
