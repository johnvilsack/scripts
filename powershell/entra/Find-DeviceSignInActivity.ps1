<#
.SYNOPSIS
Searches Entra ID Sign-in logs for activity related to a specific device name within a specified number of days.

.DESCRIPTION
This script connects to Microsoft Graph and queries the sign-in logs for entries where
the deviceDisplayName matches the provided device name. It looks back for the specified
number of days and outputs any matching log entries.

.PARAMETER DeviceName
The display name of the device to search for (e.g., "SWEETTOOTH-LT"). This is case-sensitive in Graph API filters.

.PARAMETER DaysToGoBack
The number of days to look back in the sign-in logs. Default is 14.

.EXAMPLE
.\Find-DeviceSignInActivity.ps1 -DeviceName "SWEETTOOTH-LT" -DaysToGoBack 14

.NOTES
Author: Your Name / AI Assistant
Date:   2023-10-28
Requires: Microsoft.Graph PowerShell module (Identity.SignIns or the main Microsoft.Graph module)
Permissions: AuditLog.Read.All (Delegated permissions for Graph)
Important: Device information in sign-in logs depends on how the device connects and what information is passed during authentication.
           The deviceDisplayName field in sign-in logs might not always be populated or accurate for unmanaged devices.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$DeviceName,

    [Parameter(Mandatory = $false)]
    [int]$DaysToGoBack = 14
)

# --- Script ---

Write-Host "Attempting to connect to Microsoft Graph..."
# Connect to Microsoft Graph. You might be prompted to log in.
# Scopes define the permissions the script requests.
try {
    # Ensure the module with Get-MgAuditLogSignIn is available or the generic Invoke-MgGraphRequest context
    Import-Module Microsoft.Graph.Identity.SignIns -ErrorAction SilentlyContinue
    Connect-MgGraph -Scopes "AuditLog.Read.All" -NoWelcome
    Write-Host "Successfully connected to Microsoft Graph." -ForegroundColor Green
}
catch {
    Write-Error "Failed to connect to Microsoft Graph. Ensure the 'Microsoft.Graph.Identity.SignIns' or 'Microsoft.Graph' module is installed and you have internet connectivity. Error: $($_.Exception.Message)"
    return # Exit script if connection fails
}

# Calculate the start date for the query
$startDate = (Get-Date).AddDays(-$DaysToGoBack).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
Write-Host "Searching for sign-in activity for device '$DeviceName' since $startDate (UTC)..."

$allMatchingSignIns = [System.Collections.Generic.List[PSObject]]::new()
$foundActivity = $false

try {
    # Construct the filter. Note: deviceDetail/displayName is the property for device name in sign-in logs.
    # Filters are case-sensitive for string values in Graph API.
    # We will also filter for successful sign-ins (status/errorCode eq 0) for clarity,
    # but you could remove this to see failed attempts too.
    $filter = "createdDateTime ge $startDate and deviceDetail/displayName eq '$DeviceName'"
    # You could add 'and status/errorCode eq 0' to filter for successful sign-ins only.

    $selectProperties = @(
        "id",
        "createdDateTime",
        "userDisplayName",
        "userPrincipalName",
        "appDisplayName",
        "ipAddress",
        "clientAppUsed",
        "deviceDetail", # This is an object containing displayName, operatingSystem, etc.
        "location",     # This is an object containing city, state, countryOrRegion
        "status"        # This is an object containing errorCode, failureReason
    )

    $uri = "https://graph.microsoft.com/v1.0/auditLogs/signIns?`$filter=$($filter)&`$select=$($selectProperties -join ',')&`$top=100" # Max $top is 1000 for signIns typically, but using a moderate value per page. SDK cmdlets handle paging up to 1000.

    Write-Host "Querying sign-in logs. This might take a moment..."

    # Using Invoke-MgGraphRequest for flexibility with $select and potential direct filter debugging
    $response = Invoke-MgGraphRequest -Uri $uri -Method GET

    if ($response.value.Count -gt 0) {
        $foundActivity = $true
        foreach ($signIn in $response.value) {
            $allMatchingSignIns.Add([PSCustomObject]@{
                SignInId                 = $signIn.id
                TimestampUTC             = $signIn.createdDateTime
                TimestampLocal           = ([datetime]$signIn.createdDateTime).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss')
                UserDisplayName          = $signIn.userDisplayName
                UserPrincipalName        = $signIn.userPrincipalName
                AppDisplayName           = $signIn.appDisplayName
                IPAddress                = $signIn.ipAddress
                ClientAppUsed            = $signIn.clientAppUsed
                DeviceDisplayName        = $signIn.deviceDetail.displayName
                DeviceOperatingSystem    = $signIn.deviceDetail.operatingSystem
                DeviceBrowser            = $signIn.deviceDetail.browser
                LocationCity             = $signIn.location.city
                LocationState            = $signIn.location.state
                LocationCountry          = $signIn.location.countryOrRegion
                SignInStatus             = if ($signIn.status.errorCode -eq 0) { "Success" } else { "Failure" }
                SignInFailureReason      = $signIn.status.failureReason
                SignInErrorCode          = $signIn.status.errorCode
            })
        }
    }

    # Handle pagination if @odata.nextLink exists
    while ($response.'@odata.nextLink') {
        Write-Host "Fetching next page of sign-in logs..." -ForegroundColor Yellow
        $uri = $response.'@odata.nextLink'
        $response = Invoke-MgGraphRequest -Uri $uri -Method GET
        if ($response.value.Count -gt 0) {
            $foundActivity = $true
            foreach ($signIn in $response.value) {
                 $allMatchingSignIns.Add([PSCustomObject]@{
                    SignInId                 = $signIn.id
                    TimestampUTC             = $signIn.createdDateTime
                    TimestampLocal           = ([datetime]$signIn.createdDateTime).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss')
                    UserDisplayName          = $signIn.userDisplayName
                    UserPrincipalName        = $signIn.userPrincipalName
                    AppDisplayName           = $signIn.appDisplayName
                    IPAddress                = $signIn.ipAddress
                    ClientAppUsed            = $signIn.clientAppUsed
                    DeviceDisplayName        = $signIn.deviceDetail.displayName
                    DeviceOperatingSystem    = $signIn.deviceDetail.operatingSystem
                    DeviceBrowser            = $signIn.deviceDetail.browser
                    LocationCity             = $signIn.location.city
                    LocationState            = $signIn.location.state
                    LocationCountry          = $signIn.location.countryOrRegion
                    SignInStatus             = if ($signIn.status.errorCode -eq 0) { "Success" } else { "Failure" }
                    SignInFailureReason      = $signIn.status.failureReason
                    SignInErrorCode          = $signIn.status.errorCode
                })
            }
        }
    }

    if ($foundActivity) {
        Write-Host "`nFound $($allMatchingSignIns.Count) sign-in activities matching device '$DeviceName':" -ForegroundColor Green
        $allMatchingSignIns | Format-Table TimestampLocal, UserPrincipalName, AppDisplayName, IPAddress, ClientAppUsed, DeviceOperatingSystem, SignInStatus
        
        # Optionally, export to CSV
        $csvOutputFileName = "DeviceSignInActivity-$($DeviceName -replace '[^a-zA-Z0-9_-]','_')-$(Get-Date -Format 'yyyyMMddHHmmss').csv"
        $allMatchingSignIns | Export-Csv -Path $csvOutputFileName -NoTypeInformation -Encoding UTF8
        Write-Host "`nResults also exported to: $csvOutputFileName" -ForegroundColor Cyan
    }
    else {
        Write-Host "`nNo sign-in activity found for device '$DeviceName' in the last $DaysToGoBack days with the specified filter." -ForegroundColor Yellow
        Write-Host "Things to check:"
        Write-Host " - Is the DeviceName parameter exactly matching what might appear in logs (case-sensitive)?"
        Write-Host " - Does the device actually authenticate against Entra ID for M365 services?"
        Write-Host " - The deviceDisplayName field might not be populated for all types of connections (e.g., some legacy protocols, unmanaged devices)."
        Write-Host " - Try broadening the search (e.g., remove device name filter and search by suspected user, then inspect device details)."
    }
}
catch {
    Write-Error "An error occurred while querying sign-in logs: $($_.Exception.Message)"
    Write-Host "Request URI was: $($uri)" -ForegroundColor DarkGray # Helps in debugging filter issues
}
finally {
    # Disconnect from Microsoft Graph session
    Write-Host "`nDisconnecting from Microsoft Graph."
    Disconnect-MgGraph
}

Write-Host "Script finished."