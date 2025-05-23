<#
.SYNOPSIS
Searches Exchange Online message trace logs for emails sent FROM a specific IP address.

.DESCRIPTION
This script connects to Exchange Online, performs a message trace for emails originating
from the specified IP address (using the -FromIP parameter) within a defined time range
(defaulting to the last 7 days), and displays the results.

.NOTES
- Requires the ExchangeOnlineManagement PowerShell module (EXO V2/V3). Assumes it's updated and working.
- Requires appropriate permissions in Microsoft 365 to run message traces.
- Get-MessageTrace typically searches data up to 10 days old. For older data,
  you need to use Start-HistoricalSearch which is an asynchronous task.
- Adjust the $DaysToSearch variable as needed (max 10 for Get-MessageTrace).
- Uses the -FromIP parameter as per current Microsoft documentation and confirmed working in the environment.
#>

# --- Configuration ---
$targetIP = "52.20.114.123" # The source IP address to search for
$DaysToSearch = 7         # How many days back to search (max 10 for Get-MessageTrace)

# --- Script ---

# Calculate Start and End Dates
$endDate = Get-Date
$startDate = $endDate.AddDays(-$DaysToSearch)

Write-Host "Searching for messages sent FROM IP: $targetIP" -ForegroundColor Yellow
Write-Host "Time Range: $startDate to $endDate" -ForegroundColor Yellow

# Connect to Exchange Online (will prompt for credentials if not already connected)
# You might need to specify -UserPrincipalName if you have multiple accounts configured
try {
    # Check if already connected before attempting to connect again in the same session
    $exoConnection = Get-ConnectionInformation | Where-Object {$_.ModuleName -eq 'ExchangeOnlineManagement'}
    if (-not $exoConnection) {
        Write-Host "Connecting to Exchange Online..."
        Connect-ExchangeOnline -ShowProgress $true -ErrorAction Stop
    } else {
        Write-Host "Already connected to Exchange Online."
    }
}
catch {
    Write-Error "Failed to connect to Exchange Online. Ensure the EXO module is installed and you have permissions. Error: $($_.Exception.Message)"
    Read-Host "Press Enter to exit" # Pause script on connection error
    exit
}

# Perform the Message Trace using -FromIP
Write-Host "Running message trace using -FromIP parameter... (This might take a moment)"
$messageTrace = $null # Initialize variable
try {
    # Using -FromIP parameter as confirmed working
    $messageTrace = Get-MessageTrace -FromIP $targetIP -StartDate $startDate -EndDate $endDate -PageSize 5000 -ErrorAction Stop
}
catch {
    # Catch potential errors during the trace itself (though hopefully resolved now)
    Write-Error "Error during message trace execution: $($_.Exception.Message)"
    # $messageTrace will remain $null if an error occurs here
}

# Display Results
# Check if $messageTrace is not null AND contains results (Count property exists and is > 0)
if ($null -ne $messageTrace -and $messageTrace.Count -gt 0) {
    Write-Host "Found $($messageTrace.Count) messages:" -ForegroundColor Green
    # Select relevant fields for display, FromIP is automatically included in the object properties
    $messageTrace | Select-Object Received, SenderAddress, RecipientAddress, Subject, Status, Size, MessageID, FromIP | Format-Table -AutoSize
}
elseif ($null -eq $messageTrace) {
     # This condition is met if the try/catch block above caught an error
     Write-Host "Message trace failed to execute due to the error reported above." -ForegroundColor Red
}
else {
    # This condition is met if the trace ran successfully but returned zero results
    Write-Host "No messages found sent FROM IP $targetIP in the specified time range." -ForegroundColor Red
}

# Disconnect from Exchange Online (optional, but good practice if the script connected)
# You might want to comment this out if you run multiple scripts in the same session
# Write-Host "Disconnecting from Exchange Online (if connection was made by script)..."
# if (-not $exoConnection) { # Only disconnect if the script established the connection
#     Disconnect-ExchangeOnline -Confirm:$false
# }

Write-Host "Script finished."