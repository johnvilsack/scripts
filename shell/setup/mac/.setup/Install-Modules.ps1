#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Installs or updates essential PowerShell modules for Microsoft 365 administration.

.DESCRIPTION
    This script checks for and installs/updates key PowerShell modules required to manage
    various Microsoft 365 services, including Azure Active Directory, Exchange Online,
    Microsoft Teams, and SharePoint Online.

    It requires Administrator privileges to run, as it installs modules for all users
    and manages package providers and repositories.

.NOTES
    Author: Gemini Code Assist
    Version: 1.0
    Ensure PowerShell is run as Administrator.
    An internet connection is required to download modules from the PSGallery.
    After running the script, it's recommended to close and reopen your PowerShell session.
#>

# --- Configuration: List of M365 modules to install ---
$ModulesToInstall = @(
    "MSOnline",                         # Azure Active Directory V1 (older, but still used for some tasks like licensing)
    "AzureAD",                          # Azure Active Directory V2 (being replaced by Microsoft.Graph, but widely used in existing scripts)
    "Microsoft.Graph",                  # Meta-module: Installs all v1.0 Microsoft Graph sub-modules (e.g., Identity.SignIns, Security, Files, Users, Groups, etc.)
    "Microsoft.Graph.Beta",             # Meta-module: Installs all Microsoft Graph Beta sub-modules
    "ExchangeOnlineManagement",         # For Exchange Online administration (latest version with REST API cmdlets), also includes Security & Compliance cmdlets
    "MicrosoftTeams",                   # For Microsoft Teams administration
    "PnP.PowerShell"                    # PnP PowerShell for SharePoint Online, OneDrive, Microsoft 365 Groups, Microsoft Teams, etc.
)

# --- Main Script ---

Write-Host "Starting Microsoft 365 Administration Modules Setup..." -ForegroundColor Yellow
Write-Host "This script requires Administrator privileges and an internet connection."
Write-Host "--------------------------------------------------"

# 1. Administrator Privileges are handled by #Requires -RunAsAdministrator.
#    If not run as admin, PowerShell will show an error before script execution.

# 2. Ensure NuGet Package Provider is installed
Write-Host "Checking for NuGet Package Provider..."
try {
    Get-PackageProvider -Name NuGet -ErrorAction Stop | Out-Null
    Write-Host "NuGet Package Provider is already installed." -ForegroundColor Green
}
catch {
    Write-Host "NuGet Package Provider not found. Installing..." -ForegroundColor Yellow
    try {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop
        Write-Host "NuGet Package Provider installed successfully." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to install NuGet Package Provider. $_.Exception.Message"
        Write-Error "Please install it manually (e.g., Install-PackageProvider -Name NuGet -Force) and re-run the script."
        exit 1
    }
}

# 3. Ensure PSGallery repository is trusted
Write-Host "Checking PSGallery repository status..."
$Repo = Get-PSRepository -Name "PSGallery" -ErrorAction SilentlyContinue
if ($Repo.InstallationPolicy -ne 'Trusted') {
    Write-Warning "The PSGallery repository is not trusted. Attempting to set it as trusted."
    try {
        Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted -ErrorAction Stop
        Write-Host "PSGallery repository is now trusted." -ForegroundColor Green
    }
    catch {
        Write-Warning "Could not automatically set PSGallery as trusted. $_.Exception.Message"
        Write-Warning "Module installation might require manual confirmation for each module."
    }
} else {
    Write-Host "PSGallery repository is already trusted." -ForegroundColor Green
}

# 4. Install/Update Modules
Write-Host "--------------------------------------------------"
Write-Host "Processing M365 modules..."

foreach ($moduleName in $ModulesToInstall) {
    Write-Host "--------------------------------------------------"
    Write-Host "Ensuring module '$moduleName' is installed and up-to-date..."

    try {
        $currentVersion = (Get-InstalledModule -Name $moduleName -ErrorAction SilentlyContinue).Version
        if ($currentVersion) {
            Write-Host "Module '$moduleName' is currently installed (Version: $currentVersion)."
        } else {
            Write-Host "Module '$moduleName' is not currently installed."
        }

        Write-Host "Attempting to install/update '$moduleName' from PSGallery..." -ForegroundColor Yellow
        Install-Module -Name $moduleName -Scope AllUsers -Force -AllowClobber -ErrorAction Stop
        
        $installedModule = Get-InstalledModule -Name $moduleName -ErrorAction Stop # Should exist now
        Write-Host "Successfully installed/updated '$moduleName' to version $($installedModule.Version)." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to install/update module '$moduleName'. $_.Exception.Message"
        Write-Warning "Please try installing '$moduleName' manually if issues persist: Install-Module $moduleName -Scope AllUsers -Force"
    }
}

Write-Host "--------------------------------------------------"
Write-Host "M365 module installation process completed." -ForegroundColor Green
Write-Host "IMPORTANT: Please close and reopen your PowerShell session to ensure all modules are loaded correctly and cmdlets are available."
Write-Host "--------------------------------------------------"