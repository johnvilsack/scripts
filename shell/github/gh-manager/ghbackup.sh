#!/bin/bash

# Exit on error, treat unset variables as an error, and propagate pipeline errors.
set -euo pipefail

# Script to list all your owned GitHub repositories, allow selection,
# and then clone and zip them into a ./backups folder.
# Dependencies: gh (GitHub CLI), gum (for TUI elements), zip

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Check for dependencies and GitHub CLI authentication
check_dependencies() {
  if ! command_exists gh; then
    gum style --bold --foreground "196" "Error: GitHub CLI (gh) is not installed." \
      "Please install it from https://cli.github.com/ and authenticate using 'gh auth login'."
    exit 1
  fi

  if ! command_exists gum; then
    gum style --bold --foreground "196" "Error: gum is not installed." \
      "Please install it from https://github.com/charmbracelet/gum"
    exit 1
  fi

  if ! command_exists zip; then
    gum style --bold --foreground "196" "Error: zip command is not installed." \
      "Please install it (e.g., 'sudo apt install zip' or 'brew install zip')."
    exit 1
  fi

  if ! gh auth status >/dev/null 2>&1; then
    gum style --bold --foreground "196" "Error: Not logged in to GitHub with gh CLI." \
      "Please run 'gh auth login' to authenticate."
    exit 1
  fi
}

# Fetches all repositories owned by the user and formats them for display
# Output: Each line is "OWNER/REPO"
fetch_owned_repos() {
  local gh_command_output
  local current_user
  local status_code

  # Get the currently authenticated user's login name
  current_user=$(gh api user --jq .login 2>/dev/null)
  if [[ -z "$current_user" ]]; then
    gum style --bold --foreground "196" "ERROR: Could not determine current GitHub user." \
      "Please ensure you are authenticated with 'gh auth login'."
    return 1
  fi
  gum style --faint "DEBUG: Detected current user as: $current_user"

  # Let gum spin execute the command and capture its output and status
  # Using sh -c "..." ensures the pipeline and redirection are handled as one command by gum
  # We use the fetched current_user instead of @me
  gh_command_output=$(gum spin --spinner dot --title "Fetching your owned repositories from GitHub..." --show-output -- \
    sh -c "gh repo list \"$current_user\" --json nameWithOwner --limit 10000 --jq '.[] | .nameWithOwner' 2>&1"
  )
  status_code=$? # Capture exit status of the gum spin command (which reflects sh -c)

  if [ $status_code -ne 0 ]; then
    # gum spin --show-output should have displayed the error from the command.
    # This adds a script-level confirmation of the failure.
    gum style --bold --foreground "196" "ERROR: Command to fetch repositories failed with status $status_code."
    return 1 # Propagate error
  fi

  if [[ -z "$gh_command_output" ]]; then
    gum style --italic --foreground "212" --padding "0 1" \
      "Info: The GitHub command successfully executed but returned no repositories." \
      "This could be correct, or it might indicate an issue with the query or permissions."
    # Fall through to return empty output with success status
  fi

  echo "$gh_command_output" # Return the fetched data (or empty string if none)
  return 0 # Success
}

main() {
  check_dependencies # Call dependency checks at the beginning of main

  local repos_formatted_list
  repos_formatted_list=$(fetch_owned_repos)
  local fetch_status=$? # Capture status of fetch_owned_repos itself

  if [[ $fetch_status -ne 0 ]]; then
    # Error message should have been displayed by fetch_owned_repos
    gum style --bold --foreground "196" "Exiting due to error during repository fetching."
    exit 1
  fi

  local num_repos
  if [[ -n "$repos_formatted_list" ]]; then # Only count lines if there's content
    num_repos=$(echo "$repos_formatted_list" | wc -l | tr -d '[:space:]') # Remove all whitespace
  else
    num_repos=0
  fi
  gum style --faint "DEBUG: Number of fetched/formatted repos to be listed: $num_repos"

  if [[ -z "$repos_formatted_list" || "$num_repos" -eq 0 ]]; then
    # The "Info" message from fetch_owned_repos might have already appeared.
    # This is the final user-facing message for this condition.
    gum style --padding "1" --foreground "212" "No repositories were found to backup. Exiting."
    exit 0
  fi

  gum style --border normal --margin "1" --padding "1 2" --border-foreground "212" \
    "Select repositories to backup" \
    "Use Space to select/deselect, Enter to confirm selection."

  local selected_repos_display
  IFS=$'\n' selected_repos_display=($(echo "$repos_formatted_list" | gum choose --no-limit --height 15 --header "Your Owned Repositories (Scroll with j/k or arrows):"))

  if [ ${#selected_repos_display[@]} -eq 0 ]; then
    echo "No repositories selected. Exiting."
    exit 0
  fi

  local BACKUP_DIR="./backups"
  mkdir -p "$BACKUP_DIR"
  local abs_backup_dir
  abs_backup_dir=$(realpath "$BACKUP_DIR")

  echo
  gum style --bold "You have selected the following ${#selected_repos_display[@]} repositories for backup to '$abs_backup_dir':"
  printf "%s\n" "${selected_repos_display[@]/#/- }" # Prepends "- " to each item
  echo

  if gum confirm "Proceed with backing up these ${#selected_repos_display[@]} repositories?"; then
    echo
    for repo_full_name in "${selected_repos_display[@]}"; do
      local repo_name
      repo_name=$(basename "$repo_full_name") # Extracts REPO from OWNER/REPO
      local timestamp
      timestamp=$(date +%Y%m%d-%H%M%S)
      local zip_file_name="${repo_name}_${timestamp}.zip"
      local zip_file_path="${abs_backup_dir}/${zip_file_name}"
      local temp_clone_dir

      temp_clone_dir=$(mktemp -d -t ghbackup_XXXXXX)
      if [[ ! "$temp_clone_dir" || ! -d "$temp_clone_dir" ]]; then
          gum style --foreground "196" "Failed to create temporary directory for $repo_full_name. Skipping."
          continue
      fi

      local clone_target_path="$temp_clone_dir/$repo_name"

      gum spin --spinner line --title "Cloning $repo_full_name (latest state)..." --show-output -- \
      gh repo clone "$repo_full_name" "$clone_target_path" -- --depth 1

      if [[ $? -eq 0 && -d "$clone_target_path" ]]; then
        pushd "$temp_clone_dir" > /dev/null
        gum spin --spinner line --title "Zipping $repo_name to $zip_file_name..." --show-output -- \
        zip -r "$zip_file_path" "$repo_name"
        zip_status=$?
        popd > /dev/null

        if [[ $zip_status -eq 0 ]]; then
          gum style --foreground "green" "Successfully backed up $repo_full_name to $zip_file_path."
        else
          gum style --foreground "196" "Failed to zip $repo_full_name from $clone_target_path."
        fi
      else
        gum style --foreground "196" "Failed to clone $repo_full_name or clone directory not found."
      fi

      rm -rf "$temp_clone_dir"
      # gum style --faint "Cleaned up temporary directory: $temp_clone_dir" # Optional: for more verbose output
    done
    gum style --bold --foreground "green" --padding "1 0" "Backup process complete. Archives are in $abs_backup_dir"
  else
    echo "Backup cancelled by user."
  fi
}

main