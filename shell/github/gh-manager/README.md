# GitHub TUI Management Scripts

This collection of shell scripts provides a Terminal User Interface (TUI) for managing your GitHub repositories. It includes tools for deleting forked repositories, deleting your own repositories, and backing up your repositories.

## Features

*   **Interactive TUI**: Uses `gum` for a user-friendly command-line experience.
*   **Selective Operations**: Allows you to choose specific repositories for actions.
*   **Safety Confirmations**: Includes strong confirmations before destructive operations like deletion.
*   **Modular Scripts**: Organized into individual scripts for specific tasks, managed by a central menu script.

## Scripts Overview

1.  **`ghmanage.sh`**:
    *   The main entry point.
    *   Provides a TUI menu to launch the other management scripts.

2.  **`gh_delete_forks_tui.sh`**:
    *   Lists all repositories you have forked from others on GitHub.
    *   Allows you to select multiple forked repositories.
    *   Prompts for confirmation and then deletes the selected forks from your account.

3.  **`ghmine.sh`**:
    *   Lists all repositories that you own directly (non-forks).
    *   Allows you to select multiple repositories.
    *   Prompts for confirmation and then deletes the selected repositories from your account.
    *   **Warning**: This is a destructive operation and cannot be undone.

4.  **`ghbackup.sh`**:
    *   Lists all repositories you own (both original and forked).
    *   Allows you to select multiple repositories.
    *   For each selected repository, it clones a fresh copy (latest state), zips it up, and places the archive in a `./backups` directory (created in the directory where the script is run).
    *   Zip files are timestamped (e.g., `reponame_YYYYMMDD-HHMMSS.zip`).

## Prerequisites

Before using these scripts, ensure you have the following installed and configured:

1.  **GitHub CLI (`gh`)**:
    *   Installation: cli.github.com
    *   Authentication: You must be logged in. Run `gh auth login`.
    *   **Important for Deletion Scripts**: Your `gh` token needs the `delete_repo` scope. If deletions fail with a permission error, run:
        ```bash
        gh auth refresh -h github.com -s delete_repo
        ```

2.  **`gum`**:
    *   Installation: github.com/charmbracelet/gum
    *   This provides the TUI elements.

3.  **`zip` command**:
    *   Required only for `ghbackup.sh`.
    *   Usually pre-installed on macOS and Linux. If not, install it using your system's package manager (e.g., `sudo apt install zip` on Debian/Ubuntu, `brew install zip` on macOS).

## Setup

1.  Place all the script files (`ghmanage.sh`, `gh_delete_forks_tui.sh`, `ghmine.sh`, `ghbackup.sh`) in the same directory.
2.  Make them executable:
    ```bash
    chmod +x ghmanage.sh
    chmod +x gh_delete_forks_tui.sh
    chmod +x ghmine.sh
    chmod +x ghbackup.sh
    ```

## Usage

To start, run the main management script:

```bash
./ghmanage.sh
```

This will open a TUI menu where you can select the desired action. Follow the on-screen prompts.

## :warning: Important Considerations for Deletion Scripts

*   **Irreversible Action**: Deleting repositories (`gh_delete_forks_tui.sh` and `ghmine.sh`) is a permanent action. Once a repository is deleted from GitHub, it cannot be easily recovered unless you have a separate backup.
*   **Double-Check Selections**: Always carefully review the list of repositories selected for deletion before confirming the action.
*   **Use with Caution**: These scripts are powerful. Ensure you understand what they do before running them.

## Troubleshooting

*   **Script Not Found**: If `ghmanage.sh` reports a script is not found or not executable, ensure all `.sh` files are in the same directory and have execute permissions (`chmod +x <script_name>.sh`).
*   **`@me` error / No Repos Listed (for `ghbackup.sh`)**: The `ghbackup.sh` script attempts to determine your GitHub username automatically. If this fails or if `gh repo list <your_username>` doesn't return repositories, check:
    *   Your `gh auth status`.
    *   The output of `gh api user --jq .login` (should be your username).
    *   The output of `gh repo list $(gh api user --jq .login)` run manually.
*   **Permission Errors during Deletion**: As mentioned in Prerequisites, ensure your `gh` token has the `delete_repo` scope. Run `gh auth refresh -h github.com -s delete_repo`.

## Contributing

Feel free to fork this repository, make improvements, and submit pull requests.

## License

This project is open source. Feel free to use, modify, and distribute as you see fit. (Consider adding a specific license like MIT if you prefer).