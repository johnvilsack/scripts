## Repository Overview

This repository contains a curated collection of shell and PowerShell scripts for automating IT, cloud, and system administration tasks. It is organized by platform and function, making it easy to find and use the right tool for your needs.

### Mac Setup

- **Quick Start:**  
  ```zsh
  curl -sSL "https://raw.githubusercontent.com/johnvilsack/scripts/refs/heads/main/shell/setup/mac/setup.sh" -o setup.sh && chmod +x setup.sh && ./setup.sh
  ```
  This script automates the setup of a new Mac, including Xcode tools, Rosetta, Nix, hostname configuration, and more.

---

### Shell Scripts

#### GitHub Management (`shell/github/gh-manager/`)
- **ghmanage.sh**: TUI menu for managing GitHub repositories (requires `gum`).
- **ghbackup.sh**: Backup your GitHub repositories by cloning and zipping them.
- **ghfork.sh**: List and delete forked repositories interactively.
- **ghmine.sh**: List and delete your own (non-forked) repositories interactively.

#### Google Drive Utilities (`shell/google/`)
- **getDrivebySize.sh**: Authenticates with Google Drive, lists files by size, and allows interactive deletion (requires `gum`, `jq`, `curl`, Python, and OAuth credentials).
- **getDupes.sh**: Finds and deletes duplicate large files in Google Drive interactively.

---

### PowerShell Scripts

#### Entra (Azure AD) Management (`powershell/entra/`)
- **Add-DeviceToGroup.ps1**: Add devices to Entra groups from a CSV.
- **Find-DeviceSignInActivity.ps1**: Search sign-in logs for device activity.
- **FindUsersNotInGroup.ps1**: Find users not in a specified group and export to CSV.
- **Get-EntraByDeviceModel.ps1**: Find sign-ins by device model.
- **Get-GroupExclusions.ps1**: Find users not in a group, including last sign-in info.
- **Get-SpecificMailboxRules.ps1**: Export all mailbox rules for a specific user.

#### Exchange Online (`powershell/exchange/`)
- **Get-AllMailboxRules.ps1**: Export all mailbox rules for all users.
- **CheckAcumaticaOutboundEmail.ps1**: Trace emails sent from a specific IP.
- **Search-EmailByDomain48Hours.ps1**: Trace emails sent from a specific domain in the last 48 hours.

#### SharePoint Online (`powershell/sharepoint/`)
- **Get-SharepointGroupAccess.ps1**: Audit group access across SharePoint sites.
- **Get-SharepointPermissions.ps1**: Export detailed SharePoint permissions to CSV.

---

## Usage

- Most scripts require specific dependencies (see script comments).
- PowerShell scripts are designed for use with Microsoft 365, Entra ID, Exchange Online, and SharePoint Online.
- Shell scripts are primarily for macOS and cloud automation.

