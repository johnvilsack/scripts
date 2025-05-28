<#
.SYNOPSIS
    Checks if the "All Employees" Exchange Distribution List can be found.
.DESCRIPTION
    This script connects to Exchange Online and attempts to find the
    distribution list with the display name "All Employees".
.NOTES
    Requires the Exchange Online PowerShell Module.
    Ensure you are connected to Exchange Online before running this script.
#>

# --- Connect to Exchange Online ---
try {
    Write-Host "Connecting to Exchange Online..."
    Connect-ExchangeOnline -ErrorAction Stop
    Write-Host "Successfully connected to Exchange Online."
} catch {
    Write-Error "Failed to connect to Exchange Online: $($_.Exception.Message)"
    exit 1
}

# --- Define the Distribution List Name ---
$DistributionListName = "All Employees"

# --- Attempt to find the Distribution List by Display Name ---
Write-Host "Searching for Exchange Distribution List with display name '$DistributionListName'..."
$AllEmployeesDL = Get-DistributionGroup -Filter "DisplayName -eq '$DistributionListName'"

if ($AllEmployeesDL) {
    Write-Host "Found Exchange Distribution List: $($AllEmployeesDL.Name) (Primary SMTP Address: $($AllEmployeesDL.PrimarySmtpAddress))"
} else {
    Write-Warning "Could not find an Exchange Distribution List with the display name '$DistributionListName'."
}

# --- Disconnect from Exchange Online (Optional) ---
# Disconnect-ExchangeOnline

Write-Host "--- Script complete. ---"