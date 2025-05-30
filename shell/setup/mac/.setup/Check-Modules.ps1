<#
.SYNOPSIS
    Checks if essential Microsoft 365 administration PowerShell modules are installed.

.DESCRIPTION
    This script verifies the installation status of key PowerShell modules
    used for managing Microsoft 365 services. It reports whether each module
    is found and its installed version.

.NOTES
    Author: Gemini Code Assist
    Version: 1.0
    This script does not require Administrator privileges to run, but it checks
    for modules installed for 'AllUsers' or 'CurrentUser'.
#>

# --- Configuration: List of M365 modules to check ---
# This list should ideally match the modules installed by your installation script.
$ModulesToCheck = @(
    "MSOnline",
    "AzureAD",
    "Microsoft.Graph",
    "Microsoft.Graph.Beta",
    "ExchangeOnlineManagement",
    "MicrosoftTeams",
    "PnP.PowerShell"
)

# --- Main Script ---

Write-Host "Starting Microsoft 365 Administration Modules Check..." -ForegroundColor Yellow
Write-Host "Checking for the following modules:"
$ModulesToCheck | ForEach-Object { Write-Host "- $_" }
Write-Host "--------------------------------------------------"

$installedCount = 0

foreach ($moduleName in $ModulesToCheck) {
    Write-Host "Checking for module '$moduleName'..." -NoNewline

    try {
        $moduleInfo = Get-InstalledModule -Name $moduleName -ErrorAction Stop
        Write-Host " Found. Version: $($moduleInfo.Version)" -ForegroundColor Green
        $installedCount++
    }
    catch {
        Write-Host " Not Found." -ForegroundColor Red
    }
}

Write-Host "--------------------------------------------------"
Write-Host "Module check completed." -ForegroundColor Yellow
Write-Host "$installedCount out of $($ModulesToCheck.Count) specified modules were found." -ForegroundColor Yellow
Write-Host "--------------------------------------------------"