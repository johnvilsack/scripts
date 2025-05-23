#!/bin/bash

# Script to list forked GitHub repositories and allow selective deletion via a TUI.
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
}

# Fetches forked repositories and formats them for display
# Output: Each line is "OWNER/REPO (forked from PARENT_OWNER/PARENT_REPO)"
fetch_forked_repos() {
  gum spin --spinner dot --title "Fetching your forked repositories from GitHub..." --show-output -- \
  gh repo list --fork --json nameWithOwner,parent --limit 10000 --jq \
    '.[] | .nameWithOwner + (if .parent and .parent.nameWithOwner then " (forked from " + .parent.nameWithOwner + ")" else " (parent repository details unavailable)" end)'

  # Capture the exit status of gh repo list
  # This status reflects the success of the 'gh repo list' command itself,
  # not necessarily individual jq processing errors if gh continues with a 0 exit code.
  # Removing '2>/dev/null' above helps make individual item errors visible via 'gum spin --show-output'.
  local status=$?
  if [ $status -ne 0 ]; then
    gum style --foreground "196" "Error: Failed to fetch forked repositories." \
      "Please check your internet connection and gh authentication ('gh auth status')."
    return 1
  fi
  return 0
}

main() {
  check_dependencies

  local repos_formatted_list
  repos_formatted_list=$(fetch_forked_repos)

  if [[ $? -ne 0 ]]; then
    # Error message already displayed by fetch_forked_repos
    exit 1
  fi

  # DEBUG: Check how many lines (repositories) are in repos_formatted_list
  # This helps verify if the fetching part is getting all expected repos.
  local num_repos
  num_repos=$(echo "$repos_formatted_list" | wc -l | tr -d ' ') # wc -l might have leading spaces
  gum style --faint "DEBUG: Number of fetched/formatted repos to be listed: $num_repos"

  if [[ -z "$repos_formatted_list" ]]; then
    gum style --padding "1" --foreground "212" "You have no forked repositories on GitHub."
    exit 0
  fi

  gum style --border normal --margin "1" --padding "1 2" --border-foreground "212" \
    "Select repositories to delete" \
    "Use Space to select/deselect, Enter to confirm selection."

  local selected_repos_display
  # IFS=$'\n' is crucial for handling multi-line output from gum choose correctly into an array
  IFS=$'\n' selected_repos_display=($(echo "$repos_formatted_list" | gum choose --no-limit --height 15 --header "Your Forked Repositories (Scroll with j/k or arrows):"))

  if [ ${#selected_repos_display[@]} -eq 0 ]; then
    echo "No repositories selected. Exiting."
    exit 0
  fi

  echo # Newline for better formatting
  gum style --bold "You have selected the following ${#selected_repos_display[@]} repositories for deletion:"
  for repo_display_name in "${selected_repos_display[@]}"; do
    echo "- $repo_display_name"
  done
  echo # Newline

  if gum confirm "Are you ABSOLUTELY SURE you want to delete these ${#selected_repos_display[@]} repositories? This action CANNOT be undone."; then
    echo # Newline
    for repo_display_name in "${selected_repos_display[@]}"; do
      # Extract the actual repo name (OWNER/REPO) from the formatted string
      # "OWNER/REPO (forked from PARENT_OWNER/PARENT_REPO)" -> "OWNER/REPO"
      local repo_to_delete
      repo_to_delete=$(echo "$repo_display_name" | awk '{print $1}')

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

# Run the main function
main