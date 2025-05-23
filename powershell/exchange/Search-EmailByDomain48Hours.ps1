<#
.SYNOPSIS
    Searches Exchange Online message trace logs for emails sent from a specific domain
    within the last 24 hours.

.DESCRIPTION
    This script connects to Exchange Online, performs a message trace for emails
    sent from users at "@repay.com" in the past 24 hours, displays key
    information, and offers to export the results to a CSV file.

.NOTES
    Author: Assistant
    Version: 1.1
    Requires: ExchangeOnlineManagement PowerShell module.
              Permissions to run Get-MessageTrace (e.g., View-Only Organization Management,
              Compliance Management, or a custom role with Message Tracking role).
#>

# --- Configuration ---
$SenderDomain = "@repay.com"
$HoursToSearch = 48
$CsvExportPath = ".\RepaySentMessages_Last$(New-TimeSpan -Hours $HoursToSearch | Select-Object -ExpandProperty TotalHours)h_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv" # Default CSV export path

# --- Script Body ---

Function Test-IsElevated {
    return (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

Write-Host "Starting script to search Exchange messages..." -ForegroundColor Cyan

# 1. Check and Import ExchangeOnlineManagement module
Write-Host "Checking for ExchangeOnlineManagement module..."
If (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
    Write-Warning "ExchangeOnlineManagement module is not installed."
    $installChoice = Read-Host "Do you want to try and install it now? (Requires internet and admin rights if installing for AllUsers) (Y/N)"
    If ($installChoice -eq 'Y') {
        try {
            Write-Host "Attempting to install ExchangeOnlineManagement module for the current user..."
            Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force -AllowClobber -Confirm:$false
            Write-Host "Module installed. Please re-run the script." -ForegroundColor Green
        } catch {
            Write-Error "Failed to install module: $($_.Exception.Message)"
            Write-Warning "Please install it manually using: Install-Module ExchangeOnlineManagement -Scope CurrentUser"
        }
        exit
    } else {
        Write-Warning "Module installation skipped. Script cannot continue."
        exit
    }
}

try {
    Import-Module ExchangeOnlineManagement -ErrorAction Stop
    Write-Host "ExchangeOnlineManagement module imported successfully." -ForegroundColor Green
} catch {
    Write-Error "Failed to import ExchangeOnlineManagement module: $($_.Exception.Message)"
    exit
}

# 2. Connect to Exchange Online
Write-Host "Attempting to connect to Exchange Online..."
# Check if already connected
$currentConnections = Get-ConnectionInformation -ErrorAction SilentlyContinue
if ($currentConnections -and ($currentConnections.ConnectionType -contains "ExchangeOnline")) {
    Write-Host "Already connected to Exchange Online as $($currentConnections | Where-Object {$_.ConnectionType -eq "ExchangeOnline"} | Select-Object -First 1 -ExpandProperty UserPrincipalName)." -ForegroundColor Yellow
} else {
    try {
        # Prompt for UPN if not already connected by other means (like SSO)
        $UserPrincipalName = Read-Host -Prompt "Enter your admin UserPrincipalName (e.g., admin@yourtenant.onmicrosoft.com) to connect to Exchange Online"
        Connect-ExchangeOnline -UserPrincipalName $UserPrincipalName -ShowBanner:$false -ErrorAction Stop
        Write-Host "Successfully connected to Exchange Online as $UserPrincipalName." -ForegroundColor Green
    } catch {
        Write-Error "Failed to connect to Exchange Online: $($_.Exception.Message)"
        Write-Warning "Ensure you have the correct permissions and the ExchangeOnlineManagement module is working."
        exit
    }
}

# 3. Define search parameters
$StartDate = (Get-Date).AddHours(-$HoursToSearch)
$EndDate = Get-Date
$SenderPattern = "*$($SenderDomain)" # e.g., *@repay.com

Write-Host "Searching for messages sent from '$SenderPattern' between $StartDate and $EndDate..." -ForegroundColor Cyan

# 4. Execute the search
try {
    $Messages = Get-MessageTrace -SenderAddress $SenderPattern -StartDate $StartDate -EndDate $EndDate -PageSize 5000 -ErrorAction Stop |
                Select-Object Received, SenderAddress, RecipientAddress, Subject, Status, MessageId, Size

    If ($Messages) {
        Write-Host "Found $($Messages.Count) messages." -ForegroundColor Green
        # 5. Display results on screen
        Write-Host "`n--- Search Results (first 20 or all if less) ---" -ForegroundColor Yellow
        $Messages | Select-Object -First 20 | Format-Table -AutoSize

        If ($Messages.Count -gt 20) {
            Write-Host "($($Messages.Count - 20) more messages found but not displayed here for brevity. Consider exporting.)"
        }
        Write-Host "--------------------------------------------" -ForegroundColor Yellow

        # 6. Offer to export to CSV
        $exportChoice = Read-Host "Do you want to export these $($Messages.Count) results to a CSV file? (Default path: $CsvExportPath) (Y/N)"
        If ($exportChoice -eq 'Y') {
            try {
                $Messages | Export-Csv -Path $CsvExportPath -NoTypeInformation -Encoding UTF8
                Write-Host "Results successfully exported to: $CsvExportPath" -ForegroundColor Green
            } catch {
                Write-Error "Failed to export to CSV: $($_.Exception.Message)"
            }
        } else {
            Write-Host "Export skipped."
        }
    } else {
        Write-Host "No messages found matching the criteria." -ForegroundColor Yellow
    }
} catch {
    Write-Error "An error occurred during message trace: $($_.Exception.Message)"
    # You might want to check for specific errors, like throttling, etc.
} finally {
    # 7. Disconnect the Exchange Online session
    Write-Host "Disconnecting from Exchange Online (if a session was established by this script)..."
    # Only disconnect if we initiated the connection (simplistic check here)
    # A more robust check would involve storing the connection state
    Get-PSSession | Where-Object { $_.ConfigurationName -eq 'Microsoft.Exchange' -or $_.Module -like '*ExchangeOnlineManagement*'} | ForEach-Object {
        Write-Host "Disconnecting session ID $($_.Id)..."
        Disconnect-ExchangeOnline -PSSession $_ -Confirm:$false -ErrorAction SilentlyContinue
    }
    Write-Host "Disconnected. Script finished." -ForegroundColor Cyan
}