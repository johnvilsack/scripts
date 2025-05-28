#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Groups, Microsoft.Graph.Identity.DirectoryManagement, Microsoft.Graph.Users

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
        [string[]]$Scopes = @("GroupMember.Read.All", "Device.Read.All", "User.Read.All")
    )
    try {
        Write-Host "Checking Microsoft Graph connection..."
        $connectedAccount = Get-MgContext -ErrorAction SilentlyContinue
        $allScopesPresent = $true
        foreach ($scope in $Scopes) {
            if ($connectedAccount.Scopes -notcontains $scope) {
                $allScopesPresent = $false
                break
            }
        }
        if ($null -eq $connectedAccount -or !$allScopesPresent) {
            if ($null -ne $connectedAccount) {
                Write-Host "Existing connection missing required scopes. Reconnecting..."
                Disconnect-MgGraph -ErrorAction SilentlyContinue
            } else {
                Write-Host "Not connected. Attempting to connect to Microsoft Graph..."
            }
            Connect-MgGraph -Scopes $Scopes -NoWelcome
            $connectedAccount = Get-MgContext
            if ($null -eq $connectedAccount) {
                Write-Error "Failed to connect to Microsoft Graph. Please check permissions and try again."
                return $false
            }
            Write-Host "Successfully connected to Microsoft Graph as $($connectedAccount.Account)." -ForegroundColor Green
            Write-Host "Granted Scopes: $($connectedAccount.Scopes -join ', ')" -ForegroundColor Cyan
        } else {
            Write-Host "Already connected to Microsoft Graph as $($connectedAccount.Account) with required scopes." -ForegroundColor Cyan
            Write-Host "Granted Scopes: $($connectedAccount.Scopes -join ', ')" -ForegroundColor Cyan
        }
        return $true
    }
    catch {
        Write-Error "Error during Graph connection: $($_.Exception.Message)"
        return $false
    }
}

Function Get-WindowsFeatureVersion {
    param (
        [string]$OSVersionString
    )

    if ([string]::IsNullOrWhiteSpace($OSVersionString)) {
        return "OS Version N/A"
    }

    try {
        $CurrentVersion = [System.Version]$OSVersionString
    }
    catch {
        return "Invalid OS Version Format ($OSVersionString)"
    }

    $Build = $CurrentVersion.Build

    if ($Build -gt 26100) { return "ERROR TOO HIGH" }
    if ($Build -eq 26100) { return "Windows 11 (24H2)" }
    if ($Build -eq 22631) { return "Windows 11 (23H2)" }
    if ($Build -eq 22621) { return "Windows 11 (22H2)" }
    if ($Build -eq 22000) { return "Windows 11 (21H2)" }
    if ($Build -eq 19045) { return "Windows 10 (22H2)" }
    if ($Build -eq 19044) { return "Windows 10 (21H2)" }
    if ($Build -eq 19043) { return "Windows 10 (21H1)" }
    if ($Build -eq 19042) { return "Windows 10 (20H2)" }
    if ($Build -lt 19042) { return "ERROR TOO LOW" }

    return "Unknown OS Version ($OSVersionString)"
}

# --- Main Script ---

if (-not (Connect-ToGraph)) {
    Read-Host "Press Enter to exit."
    Exit 1
}

$groupSelection = Show-Menu -Title "Select a Group" -Options $Global:EntraGroups
$selectedIndex = [int]$groupSelection - 1
if ($selectedIndex -lt 0 -or $selectedIndex -ge $Global:EntraGroups.Count) {
    Write-Error "Invalid selection. Number out of range."
    Read-Host "Press Enter to exit."
    Exit 1
}

$selectedGroupName = $Global:EntraGroups[$selectedIndex]
Write-Host "`nFetching members for group: $selectedGroupName" -ForegroundColor Yellow

try {
    $group = Get-MgGroup -Filter "displayName eq '$selectedGroupName'" -ErrorAction Stop
    $groupMembers = Get-MgGroupTransitiveMember -GroupId $group.Id -All -ErrorAction Stop
    $deviceMembers = $groupMembers | Where-Object { $_.AdditionalProperties["@odata.type"] -eq "#microsoft.graph.device" }

    if (-not $deviceMembers) {
        Write-Host "No devices found in group '$selectedGroupName'." -ForegroundColor Cyan
        Read-Host "Press Enter to exit."
        Exit 0
    }

    $report = @()
    $totalDevices = $deviceMembers.Count
    $processedCount = 0

    Write-Host "Processing $($totalDevices) devices..."

    foreach ($memberDevice in $deviceMembers) {
        $processedCount++
        Write-Progress -Activity "Fetching Device Details" -Status "Processing device $processedCount of $totalDevices" -PercentComplete (($processedCount / $totalDevices) * 100)

        try {
            $deviceDetails = Get-MgDevice -DeviceId $memberDevice.Id -Property "id,displayName,operatingSystemVersion" -ErrorAction Stop
            $deviceName = $deviceDetails.DisplayName
            $osVersion = $deviceDetails.OperatingSystemVersion
            $userPrincipalName = "N/A"

            try {
                $registeredDirectoryObjects = Get-MgDeviceRegisteredUser -DeviceId $deviceDetails.Id -ErrorAction SilentlyContinue

                $firstUserObject = $registeredDirectoryObjects | Where-Object {
                    $_.AdditionalProperties["@odata.type"] -eq "#microsoft.graph.user"
                } | Select-Object -First 1

                if ($firstUserObject) {
                    $userPrincipalName = $firstUserObject.AdditionalProperties["userPrincipalName"]
                    if (-not $userPrincipalName -and $firstUserObject.Id) {
                        try {
                            $specificUser = Get-MgUser -UserId $firstUserObject.Id -Property UserPrincipalName -ErrorAction Stop
                            $userPrincipalName = $specificUser.UserPrincipalName
                        } catch {
                            $userPrincipalName = "<UPN lookup failed for $($firstUserObject.Id)>"
                        }
                    } elseif (-not $userPrincipalName) {
                        $userPrincipalName = "<User object found, no UPN>"
                    }
                } else {
                    $userPrincipalName = "<No user-type entities registered>"
                }
            } catch {
                $userPrincipalName = "<Error fetching UPN>"
            }

            $featureVersion = Get-WindowsFeatureVersion -OSVersionString $osVersion

            $report += [PSCustomObject]@{
                DeviceName = $deviceName
                UserPrincipalName = $userPrincipalName
                OSVersionRaw = $osVersion
                WindowsFeatureVersion = $featureVersion
            }
        } catch {
            $report += [PSCustomObject]@{
                DeviceName = $memberDevice.Id
                UserPrincipalName = "Error"
                OSVersionRaw = "Error"
                WindowsFeatureVersion = "Error retrieving details"
            }
        }
    }
    Write-Progress -Activity "Fetching Device Details" -Completed

    Clear-Host
    Write-Host "--- Device Report for Group: $selectedGroupName ---" -ForegroundColor Cyan

    if ($report.Count -eq 0) {
        Write-Host "No device data to display."
    } else {
        $format = "{0,-30}{1,-40}{2,-25}"
        Write-Host ($format -f "Device Name", "User Principal Name", "Windows Version")
        Write-Host ($format -f ('-'*30), ('-'*40), ('-'*25))
        foreach ($item in $report) {
            $line = ($format -f $item.DeviceName, $item.UserPrincipalName, $item.WindowsFeatureVersion)
            if ($item.WindowsFeatureVersion -eq "Windows 11 (24H2)") {
                Write-Host $line -ForegroundColor Green
            } else {
                Write-Host $line
            }
        }
    }
    Write-Host "----------------------------------------------------"
    Write-Host "Report complete. Processed $($report.Count) devices."

} catch {
    Write-Error "An unhandled error occurred: $($_.Exception.Message)"
} finally {
    Read-Host "Press Enter to exit."
}