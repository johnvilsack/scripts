#!/bin/bash

# ghmanage.sh - A TUI menu to manage GitHub repositories using other scripts.
# Dependencies: gum, and the scripts it calls (gh_delete_forks_tui.sh, ghmine.sh, ghbackup.sh)

# Exit on error, treat unset variables as an error.
set -euo pipefail

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Check for gum dependency
check_gum_dependency() {
  if ! command_exists gum; then
    echo "Error: gum is not installed."
    echo "Please install it from https://github.com/charmbracelet/gum"
    exit 1
  fi
}

# Get the directory where this script is located
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# Define paths to the other scripts (assuming they are in the same directory)
FORK_DELETE_SCRIPT="$SCRIPT_DIR/gh_delete_forks_tui.sh"
MINE_DELETE_SCRIPT="$SCRIPT_DIR/ghmine.sh"
BACKUP_SCRIPT="$SCRIPT_DIR/ghbackup.sh"

# Function to display the main menu and handle selections
main_menu() {
  while true; do
    gum style --border normal --margin "1" --padding "1 2" --border-foreground "240" \
      "GitHub Repository Management Menu"

    local choice
    choice=$(gum choose \
      "Delete Forked Repositories" \
      "Delete My Owned Repositories (Non-Forks)" \
      "Backup My Owned Repositories" \
      "Exit" \
      --header "Select an action:" --height 10)

    case "$choice" in
      "Delete Forked Repositories")
        if [ -x "$FORK_DELETE_SCRIPT" ]; then
          "$FORK_DELETE_SCRIPT"
        else
          gum style --bold --foreground "196" "Error: Script not found or not executable: $FORK_DELETE_SCRIPT"
        fi
        ;;
      "Delete My Owned Repositories (Non-Forks)")
        if [ -x "$MINE_DELETE_SCRIPT" ]; then
          "$MINE_DELETE_SCRIPT"
        else
          gum style --bold --foreground "196" "Error: Script not found or not executable: $MINE_DELETE_SCRIPT"
        fi
        ;;
      "Backup My Owned Repositories")
        if [ -x "$BACKUP_SCRIPT" ]; then
          "$BACKUP_SCRIPT"
        else
          gum style --bold --foreground "196" "Error: Script not found or not executable: $BACKUP_SCRIPT"
        fi
        ;;
      "Exit")
        gum style --italic "Exiting GitHub Management Menu."
        exit 0
        ;;
      *)
        # This case handles pressing Esc or if gum choose returns empty
        gum style --italic "No selection made or menu cancelled. Exiting."
        exit 0
        ;;
    esac
    gum input --placeholder "Press Enter to return to the menu..." > /dev/null
  done
}

# --- Main Script Execution ---
check_gum_dependency
main_menu