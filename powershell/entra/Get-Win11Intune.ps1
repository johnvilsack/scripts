#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Groups, Microsoft.Graph.Identity.DirectoryManagement, Microsoft.Graph.Users, Microsoft.Graph.DeviceManagement

param(
    [switch]$upn
)
Write-Host "Invoke with -upn to list only email addresses"

# --- Configuration ---
$Global:EntraGroups = @(
    "Win11_Ring_0",
    "Win11_Ring_1",
    "Win11_Ring_2",
    "Win11_Ring_3"
)

# --- Functions ---

Function Show-Menu {
    param(
        [string]$Title = "Select an Option",
        [string[]]$Options
    )
    Clear-Host
    Write-Host "================ $Title ================"
    For ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host ("[{0}] {1}" -f ($i + 1), $Options[$i])
    }
    Write-Host "=============================================="
    $selection = Read-Host "Enter your choice (number)"
    return $selection
}

Function Connect-ToGraph {
    param (
        [string[]]$Scopes = @("GroupMember.Read.All", "Device.Read.All", "User.Read.All", "DeviceManagementManagedDevices.Read.All")
    )
    try {
        $ctx = Get-MgContext -ErrorAction SilentlyContinue
        if ($null -eq $ctx -or ($Scopes | Where-Object { $ctx.Scopes -notcontains $_ })) {
            Disconnect-MgGraph -ErrorAction SilentlyContinue
            Connect-MgGraph -Scopes $Scopes -NoWelcome
            $ctx = Get-MgContext
            if ($null -eq $ctx) {
                Write-Error "Failed to connect to Microsoft Graph."
                return $false
            }
        }
        Write-Host "Connected as $($ctx.Account)" -ForegroundColor Green
        return $true
    } catch {
        Write-Error "Graph connection failed: $($_.Exception.Message)"
        return $false
    }
}

Function Get-WindowsFeatureVersion {
    param ([string]$OSVersionString)

    try {
        $ver = [System.Version]$OSVersionString
        switch ($ver.Build) {
            { $_ -gt 26100 } { return "ERROR TOO HIGH" }
            26100 { return "Windows 11 (24H2)" }
            22631 { return "Windows 11 (23H2)" }
            22621 { return "Windows 11 (22H2)" }
            22000 { return "Windows 11 (21H2)" }
            19045 { return "Windows 10 (22H2)" }
            19044 { return "Windows 10 (21H2)" }
            19043 { return "Windows 10 (21H1)" }
            19042 { return "Windows 10 (20H2)" }
            { $_ -lt 19042 } { return "ERROR TOO LOW" }
            default { return "Unknown OS Version ($OSVersionString)" }
        }
    } catch {
        return "Invalid OS Version Format ($OSVersionString)"
    }
}

# --- Main Execution ---

if (-not (Connect-ToGraph)) {
    Read-Host "Press Enter to exit."
    Exit 1
}

$groupSelection = Show-Menu -Title "Select a Group" -Options $Global:EntraGroups
$selectedIndex = [int]$groupSelection - 1
if ($selectedIndex -lt 0 -or $selectedIndex -ge $Global:EntraGroups.Count) {
    Write-Error "Invalid selection."
    Exit 1
}

$groupName = $Global:EntraGroups[$selectedIndex]
Write-Host "`nFetching members for: $groupName" -ForegroundColor Yellow

try {
    $group = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction Stop
    $members = Get-MgGroupTransitiveMember -GroupId $group.Id -All -ErrorAction Stop
    $devices = $members | Where-Object { $_.AdditionalProperties["@odata.type"] -eq "#microsoft.graph.device" }

    if (-not $devices) {
        Write-Host "No devices found." -ForegroundColor Cyan
        Exit 0
    }

    $report = @()
    $i = 0
    foreach ($dev in $devices) {
        $i++
        Write-Progress -Activity "Processing Devices" -Status "Device $i of $($devices.Count)" -PercentComplete (($i / $devices.Count) * 100)
        try {
            $deviceDetails = Get-MgDevice -DeviceId $dev.Id -ErrorAction Stop
            $entraOS = $deviceDetails.OperatingSystemVersion
            $entraLast = if ($deviceDetails.ApproximateLastSignInDateTime) { 
                Get-Date $deviceDetails.ApproximateLastSignInDateTime -Format 'yyyy-MM-dd HH:mm:ss'
            } else { "N/A" }

            $userPrincipalName = "<Not Found>"

            $users = Get-MgDeviceRegisteredUser -DeviceId $deviceDetails.Id -ErrorAction SilentlyContinue
            $userObj = $users | Where-Object { $_.AdditionalProperties["@odata.type"] -eq "#microsoft.graph.user" } | Select-Object -First 1

            if ($userObj) {
                $userId = $userObj.Id
                $userInfo = Get-MgUser -UserId $userId -Property "UserPrincipalName" -ErrorAction SilentlyContinue
                if ($userInfo) { $userPrincipalName = $userInfo.UserPrincipalName }
            }

            $intuneOS = "N/A"
            $lastSync = "N/A"
            $featureSource = $entraOS

            $intuneDev = Get-MgDeviceManagementManagedDevice -Filter "azureADDeviceId eq '$($deviceDetails.DeviceId)'" -Top 1 -ErrorAction SilentlyContinue
            if ($intuneDev) {
                $intuneOS = $intuneDev.OsVersion
                $featureSource = $intuneDev.OsVersion
                $lastSync = if ($intuneDev.LastSyncDateTime) {
                    Get-Date $intuneDev.LastSyncDateTime -Format 'yyyy-MM-dd HH:mm:ss'
                } else {
                    "No Sync"
                }
            }

            $report += [pscustomobject]@{
                DeviceName = $deviceDetails.DisplayName
                UserPrincipalName = $userPrincipalName
                OSVersionRaw = $intuneOS
                WindowsFeatureVersion = Get-WindowsFeatureVersion -OSVersionString $featureSource
                EntraLastActivity = $entraLast
                IntuneLastCheckin = $lastSync
            }
        } catch {
            Write-Warning "Device $($dev.Id) failed: $($_.Exception.Message)"
        }
    }

    Write-Progress -Activity "Processing Devices" -Completed

    if ($upn) {
        $report | Where-Object { $_.UserPrincipalName -ne "<Not Found>" } | ForEach-Object {
            if ($_.WindowsFeatureVersion -eq "Windows 11 (24H2)") {
                Write-Host $_.UserPrincipalName -ForegroundColor Green
            } else {
                Write-Host $_.UserPrincipalName
            }
        }
        Exit 0
    }

    Clear-Host
    Write-Host "--- Device Report for $groupName ---" -ForegroundColor Cyan

    $fmt = "{0,-25}{1,-35}{2,-20}{3,-22}{4,-22}"
    Write-Host ($fmt -f "Device Name", "User Principal Name", "Windows Version", "Entra Last Activity", "Intune Last Checkin")
    Write-Host ($fmt -f ('-'*25), ('-'*35), ('-'*20), ('-'*22), ('-'*22))

    foreach ($row in $report) {
        $line = $fmt -f $row.DeviceName, $row.UserPrincipalName, $row.WindowsFeatureVersion, $row.EntraLastActivity, $row.IntuneLastCheckin
        if ($row.WindowsFeatureVersion -eq "Windows 11 (24H2)") {
            Write-Host $line -ForegroundColor Green
        } else {
            Write-Host $line
        }
    }

    Write-Host "--------------------------------------------------"
    Write-Host "Report completed for $($report.Count) devices."

} catch {
    Write-Error "Unhandled error: $($_.Exception.Message)"
} finally {
    Read-Host "Press Enter to exit."
}
