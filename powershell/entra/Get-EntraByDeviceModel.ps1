<#
.SYNOPSIS
    Searches Entra ID (Azure AD) sign-in logs for logins from devices of a specific model.

.DESCRIPTION
    This script first identifies devices in Azure AD that match a specified model name.
    Then, for each identified device, it queries the Azure AD sign-in logs for login events.
    This script requires the Microsoft Graph PowerShell SDK to be installed and appropriate permissions.

.PARAMETER ModelName
    The device model name to search for (e.g., "Inspiron 5537").

.EXAMPLE
    .\Get-SignInsByDeviceModel.ps1 -ModelName "Inspiron 5537"

    This will search for sign-ins from all devices with the model "Inspiron 5537".

.NOTES
    Author: AI Assistant
    Date:   2025-05-13 (based on user interaction date)
    Requires: Microsoft.Graph.Authentication, Microsoft.Graph.Identity.DirectoryManagement, Microsoft.Graph.Reports
    Permissions needed for Microsoft Graph: Device.Read.All, AuditLog.Read.All
#>

param (
    [Parameter(Mandatory=$true)]
    [string]$ModelName = "Inspiron 5537" # Default example, but mandatory means user must provide or confirm
)

# --- Ensure connection to Microsoft Graph ---
# Uncomment and run the Connect-MgGraph line if you are not already connected.
# You might need to adjust scopes based on your tenant's policies or if you need other permissions.
# $RequiredScopes = @("Device.Read.All", "AuditLog.Read.All")
# Connect-MgGraph -Scopes $RequiredScopes

# Check if connected, if not, provide guidance
try {
    Get-MgContext -ErrorAction Stop | Out-Null
    Write-Host "Successfully connected to Microsoft Graph." -ForegroundColor Green
}
catch {
    Write-Error "Not connected to Microsoft Graph. Please run: Connect-MgGraph -Scopes 'Device.Read.All', 'AuditLog.Read.All'"
    exit 1
}

# --- Step 1: Find Device IDs for the specific model (Client-side filtering) ---
Write-Host "Step 1: Identifying devices with model '$ModelName'..." -ForegroundColor Cyan

Write-Host "Fetching all Azure AD devices... This may take a while for large environments."
try {
    # Get devices, selecting only necessary properties.
    # -All ensures all pages are retrieved.
    # We will filter client-side because 'model' is not server-side filterable via -Filter.
    $allTenantDevices = Get-MgDevice -All -Property Id, DeviceId, DisplayName, Model, OperatingSystem -ErrorAction Stop
}
catch {
    Write-Error "Failed to retrieve devices from Azure AD. Error: $($_.Exception.Message)"
    exit 1
}

if (-not $allTenantDevices) {
    Write-Warning "No devices found in the tenant at all."
    exit
}

# Client-side filtering for the model
# Using -match for a case-insensitive substring match. Use -eq for exact case-insensitive match.
# Or $_.Model -ccontains $ModelName for case-sensitive contains
$matchingDevices = $allTenantDevices | Where-Object { $_.Model -match [regex]::Escape($ModelName) }
# For an exact, case-insensitive match:
# $matchingDevices = $allTenantDevices | Where-Object { $_.Model -eq $ModelName }

if (-not $matchingDevices) {
    Write-Warning "No devices found with model containing '$ModelName' after client-side filtering."
    exit
}

$deviceIds = $matchingDevices.DeviceId
Write-Host "Found $($matchingDevices.Count) device(s) with model containing '$ModelName':" -ForegroundColor Green
$matchingDevices | ForEach-Object {
    Write-Host "  - DisplayName: $($_.DisplayName), DeviceId: $($_.DeviceId), OS: $($_.OperatingSystem), Model: $($_.Model)"
}
Write-Host "" # Newline for better readability

# --- Step 2: Query Sign-in Logs for those Device IDs ---
if ($deviceIds.Count -eq 0) {
    Write-Host "No device IDs found matching the model. Skipping sign-in log search."
    exit
}

Write-Host "Step 2: Fetching sign-ins for the identified device(s)..." -ForegroundColor Cyan
$allSignInsFromMatchingDevices = [System.Collections.Generic.List[object]]::new()

foreach ($devId in $deviceIds) {
    $deviceDisplayName = ($matchingDevices | Where-Object {$_.DeviceId -eq $devId}).DisplayName | Select-Object -First 1
    $deviceActualModel = ($matchingDevices | Where-Object {$_.DeviceId -eq $devId}).Model | Select-Object -First 1
    Write-Host "Fetching sign-ins for Device: '$deviceDisplayName' (ID: $devId, Model: '$deviceActualModel')"

    try {
        # The DeviceId from Get-MgDevice is the Azure AD Device ID.
        # Query sign-in logs for the last 90 days by default. Adjust -Top or handle paging for more.
        # You can add a date filter here too e.g. -Filter "createdDateTime ge YYYY-MM-DDTHH:MM:SSZ and deviceId eq '$devId'"
        $signInsForDevice = Get-MgAuditLogSignIn -Filter "deviceId eq '$devId'" -Top 100 -ErrorAction Stop

        if ($signInsForDevice) {
            # Add device model and display name to each sign-in record for easier reporting
            $signInsForDevice | ForEach-Object {
                $_ | Add-Member -MemberType NoteProperty -Name "QueriedDeviceModel" -Value $deviceActualModel
                $_ | Add-Member -MemberType NoteProperty -Name "QueriedDeviceDisplayName" -Value $deviceDisplayName
                $allSignInsFromMatchingDevices.Add($_)
            }
            Write-Host "  Found $($signInsForDevice.Count) sign-in(s) for device '$deviceDisplayName'." -ForegroundColor Green
        } else {
            Write-Host "  No sign-ins found for device '$deviceDisplayName' (ID: $devId) in the queried period."
        }
    } catch {
        # Using ${devId} to ensure proper variable expansion when followed by a colon
        Write-Warning "Error fetching sign-ins for Device ID ${devId} ('$deviceDisplayName'): $($_.Exception.Message)"
    }
}

# --- Step 3: Output Results ---
Write-Host ""
if ($allSignInsFromMatchingDevices.Count -gt 0) {
    Write-Host "Step 3: Sign-in Log Results for devices matching model '$ModelName'" -ForegroundColor Cyan
    Write-Host "Found $($allSignInsFromMatchingDevices.Count) total sign-in(s) from these devices." -ForegroundColor Green

    # Output selected properties. DeviceDetail itself is an object, you might want to expand its properties.
    $allSignInsFromMatchingDevices | Select-Object -Property `
        CreatedDateTime, `
        UserDisplayName, `
        UserPrincipalName, `
        AppDisplayName, `
        IpAddress, `
        @{Name="Location"; Expression = {$_.Location.City + ", " + $_.Location.CountryOrRegion}}, `
        @{Name="DeviceModelReported"; Expression = {$_.DeviceDetail.deviceModel}}, `
        @{Name="DeviceOSReported"; Expression = {$_.DeviceDetail.operatingSystem}}, `
        QueriedDeviceDisplayName, `
        QueriedDeviceModel, `
        Status `
        | Format-Table -AutoSize

    # For more detailed DeviceDetail:
    # $allSignInsFromMatchingDevices | Select-Object UserPrincipalName, CreatedDateTime, AppDisplayName, @{N="DeviceModel";E={$_.DeviceDetail.deviceModel}}, @{N="DeviceOS";E={$_.DeviceDetail.operatingSystem}}
} else {
    Write-Warning "No sign-ins found from any of the devices matching model '$ModelName'."
}

Write-Host "Script finished."

# --- Optional: Disconnect from Microsoft Graph ---
# If you want to disconnect after the script runs:
# Write-Host "Disconnecting from Microsoft Graph..."
# Disconnect-MgGraph