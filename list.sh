#!/bin/bash

# list.sh - List Inference Snaps Version Information
#
# This script fetches and displays version information for all inference snaps
# from the GitHub repositories tagged with 'inference-snaps'.
#
# Usage:
#   ./list.sh
#
# Output:
#   - Repository name
#   - Snap version (from snap/snapcraft.yaml)
#   - CLI version (from inference-snaps-cli used by the snap)
#
# Requirements:
#   - curl (for fetching data from GitHub)
#   - Internet connection

# Color codes for pretty output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# GitHub API base URL
GITHUB_API="https://api.github.com"
GITHUB_RAW="https://raw.githubusercontent.com"
GITHUB_TOPIC_URL="https://github.com/topics/inference-snap"

# Fetch list of repositories from GitHub API using the topic search
API_RESPONSE=$(curl -s --max-time 15 "${GITHUB_API}/search/repositories?q=topic:inference-snap+org:canonical&per_page=100" 2>/dev/null || echo "")

if [ -z "$API_RESPONSE" ]; then
    echo "Error: Could not fetch repository list from GitHub API"
    exit 1
fi

# Extract repository full names (canonical/repo-name)
INFERENCE_SNAPS=($(echo "$API_RESPONSE" | grep -oP '"full_name":\s*"\K[^"]+' | sort))

if [ ${#INFERENCE_SNAPS[@]} -eq 0 ]; then
    echo "Error: Found no repositories with 'inference-snap' topic"
    exit 1
fi

echo "Found ${#INFERENCE_SNAPS[@]} repositories with 'inference-snap' topic"

# Get CLI version from inference-snaps-cli
CLI_VERSION=$(curl -s --max-time 10 "${GITHUB_API}/repos/canonical/inference-snaps-cli/releases" 2>/dev/null | \
    grep -m 1 '"tag_name":' | \
    sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')

if [ -z "$CLI_VERSION" ]; then
    CLI_VERSION="N/A"
    echo "Warning: Could not fetch CLI version"
else
    echo "Latest CLI Release: ${CLI_VERSION}"
fi
echo ""

printf "${BOLD}%-30s %-20s %-20s${NC}\n" "REPOSITORY" "SNAP VERSION" "CLI VERSION"

for repo in "${INFERENCE_SNAPS[@]}"; do
    # Extract owner and repo name
    REPO_NAME=$(basename "$repo")
    
    # Fetch snapcraft.yaml from the main branch
    SNAPCRAFT_URL="${GITHUB_RAW}/${repo}/main/snap/snapcraft.yaml"
    
    # Attempt to fetch snapcraft.yaml with timeout
    SNAPCRAFT_CONTENT=$(curl -s -f --max-time 10 "$SNAPCRAFT_URL" 2>/dev/null || echo "")
    
    if [ -n "$SNAPCRAFT_CONTENT" ]; then
        # Extract version from snapcraft.yaml
        # Try multiple patterns as different snaps use different version definitions
        
        # Pattern 1: version: &snap-version "v1.0.0"
        SNAP_VERSION=$(echo "$SNAPCRAFT_CONTENT" | grep -oP 'version:\s*&[a-z-]*\s*"\K[^"]+' | head -1)
        
        # Pattern 2: adopt-info: version (dynamic version)
        if [ -z "$SNAP_VERSION" ]; then
            ADOPT_INFO=$(echo "$SNAPCRAFT_CONTENT" | grep -oP 'adopt-info:\s*\K\w+')
            if [ -n "$ADOPT_INFO" ]; then
                # Look for the version construction in the part
                # Extract the version pattern from craftctl set version="..."
                VERSION_PATTERN=$(echo "$SNAPCRAFT_CONTENT" | grep -oP 'craftctl set version="\K[^"]+' | head -1)
                
                if [ -n "$VERSION_PATTERN" ]; then
                    # Try to construct a representative version
                    # Replace git command patterns and variable substitutions with placeholders
                    SNAP_VERSION=$(echo "$VERSION_PATTERN" | sed -e 's/\$([^)]*)/<git>/g' -e 's/\$[a-zA-Z_][a-zA-Z0-9_]*/<var>/g')
                else
                    SNAP_VERSION="(dynamic)"
                fi
            fi
        fi
        
        # Pattern 3: version: "string" or version: string
        if [ -z "$SNAP_VERSION" ]; then
            SNAP_VERSION=$(echo "$SNAPCRAFT_CONTENT" | grep -oP '^version:\s*"\K[^"]+' | head -1)
        fi
        
        if [ -z "$SNAP_VERSION" ]; then
            SNAP_VERSION=$(echo "$SNAPCRAFT_CONTENT" | grep -oP '^version:\s*\K[^\s]+' | head -1)
        fi
        
        # Extract CLI version from snapcraft.yaml
        # Look for CLI source URL with version tag
        SNAP_CLI_VERSION=$(echo "$SNAPCRAFT_CONTENT" | \
            grep -oP 'inference-snaps-cli/releases/download/\K[^/]+' | head -1)
        
        if [ -z "$SNAP_CLI_VERSION" ]; then
            # Try to find it in the CLI part source-tag
            SNAP_CLI_VERSION=$(echo "$SNAPCRAFT_CONTENT" | \
                grep -A 3 "plugin: go" | \
                grep -oP 'source-tag:\s*\K\S+' | head -1)
        fi
        
        # If this is the CLI repo itself, use the fetched CLI version
        if [ "$REPO_NAME" = "inference-snaps-cli" ]; then
            SNAP_CLI_VERSION="$CLI_VERSION"
        fi
        
        # Default values if not found
        [ -z "$SNAP_VERSION" ] && SNAP_VERSION="N/A"
        [ -z "$SNAP_CLI_VERSION" ] && SNAP_CLI_VERSION="N/A"
        
        # Choose color for CLI version: green if it matches latest, yellow otherwise
        if [ "$SNAP_CLI_VERSION" = "$CLI_VERSION" ]; then
            CLI_COLOR="${GREEN}"
        else
            CLI_COLOR="${YELLOW}"
        fi
        
        # Print with proper spacing (%-30s for repo, %-20s for versions)
        printf "%-30s " "$REPO_NAME"
        printf "%-20s " "$SNAP_VERSION"
        printf "${CLI_COLOR}%-20s${NC}\n" "$SNAP_CLI_VERSION"
    else
        # No snapcraft.yaml found
        printf "%-30s " "$REPO_NAME"
        printf "%-20s " "No snapcraft.yaml"
        printf "%-20s\n" "N/A"
    fi
done
