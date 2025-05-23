#!/bin/bash

# Script to list your own (non-forked) GitHub repositories and allow selective deletion via a TUI.
# Dependencies: gh (GitHub CLI), gum (for TUI elements)

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Check for dependencies and GitHub CLI authentication
check_dependencies() {
  if ! command_exists gh; then
    echo "Error: GitHub CLI (gh) is not installed."
    echo "Please install it from https://cli.github.com/ and authenticate using 'gh auth login'."
    exit 1
  fi

  if ! command_exists gum; then
    echo "Error: gum is not installed."
    echo "Please install it from https://github.com/charmbracelet/gum"
    exit 1
  fi

  if ! gh auth status >/dev/null 2>&1; then
    echo "Error: Not logged in to GitHub with gh CLI."
    echo "Please run 'gh auth login' to authenticate."
    exit 1
  fi

  # Proactively check if the 'delete_repo' scope might be missing
  local auth_status_output
  auth_status_output=$(gh auth status 2>&1)

  if echo "$auth_status_output" | grep -q "Logged in to github.com" && \
     ! echo "$auth_status_output" | grep -q "Token scopes:.*delete_repo"; then
    gum style --border normal --margin "1" --padding "1" --border-foreground "yellow" \
      "Warning: Your GitHub CLI token might be missing the 'delete_repo' scope." \
      "This script requires it to delete repositories." \
      "If deletions fail with a permission error, please run:" \
      "  gh auth refresh -h github.com -s delete_repo"
  fi
}

# Fetches your own (non-forked) repositories and formats them for display
# Output: Each line is "OWNER/REPO"
fetch_my_repos() {
  gum spin --spinner dot --title "Fetching your repositories from GitHub..." --show-output -- \
  gh repo list --source --json nameWithOwner --limit 10000 --jq '.[] | .nameWithOwner'

  local status=$?
  if [ $status -ne 0 ]; then
    gum style --foreground "196" "Error: Failed to fetch your repositories." \
      "Please check your internet connection and gh authentication ('gh auth status')."
    return 1
  fi
  return 0
}

main() {
  check_dependencies

  local repos_formatted_list
  repos_formatted_list=$(fetch_my_repos)

  if [[ $? -ne 0 ]]; then
    exit 1
  fi

  local num_repos
  num_repos=$(echo "$repos_formatted_list" | wc -l | tr -d ' ')
  gum style --faint "DEBUG: Number of fetched/formatted repos to be listed: $num_repos"

  if [[ -z "$repos_formatted_list" ]]; then
    gum style --padding "1" --foreground "212" "You have no repositories that you own directly (non-forks)."
    exit 0
  fi

  gum style --border normal --margin "1" --padding "1 2" --border-foreground "212" \
    "Select your repositories to delete" \
    "Use Space to select/deselect, Enter to confirm selection."

  local selected_repos_display
  IFS=$'\n' selected_repos_display=($(echo "$repos_formatted_list" | gum choose --no-limit --height 15 --header "Your Repositories (Scroll with j/k or arrows):"))

  if [ ${#selected_repos_display[@]} -eq 0 ]; then
    echo "No repositories selected. Exiting."
    exit 0
  fi

  echo
  gum style --bold "You have selected the following ${#selected_repos_display[@]} repositories for deletion:"
  printf "%s\n" "${selected_repos_display[@]/#/- }" # Prepends "- " to each item
  echo

  if gum confirm "Are you ABSOLUTELY SURE you want to delete these ${#selected_repos_display[@]} repositories? This action CANNOT be undone."; then
    echo
    for repo_to_delete in "${selected_repos_display[@]}"; do
      gum spin --spinner line --title "Attempting to delete $repo_to_delete..." --show-output -- \
      gh repo delete "$repo_to_delete" --yes
      if [[ $? -eq 0 ]]; then
        gum style --foreground "green" "Successfully deleted $repo_to_delete."
      else
        gum style --foreground "red" "Failed to delete $repo_to_delete. It might have already been deleted, or an error occurred."
      fi
    done
    gum style --bold --foreground "green" --padding "1 0" "Deletion process complete."
  else
    echo "Deletion cancelled by user."
  fi
}

main