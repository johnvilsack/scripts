# Script to add csv of DeviceName, GroupName to Entra Groups

# Load Microsoft Graph if not already available
# Install-Module Microsoft.Graph -Scope CurrentUser -AllowClobber

Import-Module Microsoft.Graph
Connect-MgGraph -Scopes "Group.ReadWrite.All", "Device.Read.All", "Directory.Read.All"

# Path to CSV (in same directory as script)
$csvPath = "./devices.csv"

# Import CSV
$rows = Import-Csv -Path $csvPath

foreach ($row in $rows) {
    $deviceName = $row.DeviceName.Trim()
    $groupName  = $row.GroupName.Trim()

    # Get device object
    $device = Get-MgDevice -Filter "displayName eq '$deviceName'" -ConsistencyLevel eventual
    if (-not $device) {
        Write-Warning ("Device not found: {0}" -f $deviceName)
        continue
    }

    # Get group object
    $group = Get-MgGroup -Filter "displayName eq '$groupName'" -ConsistencyLevel eventual
    if (-not $group) {
        Write-Warning ("Group not found: {0}" -f $groupName)
        continue
    }

    # Add device to group
    try {
        New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $device.Id
        Write-Host ("Added {0} to {1}" -f $deviceName, $groupName)
    }
    catch {
        if ($_ -match "added object references already exist") {
            Write-Host ("{0} is already in {1}" -f $deviceName, $groupName)
        } else {
            Write-Warning ("Failed to add {0} to {1}: {2}" -f $deviceName, $groupName, $_.Exception.Message)
        }
    }
}
