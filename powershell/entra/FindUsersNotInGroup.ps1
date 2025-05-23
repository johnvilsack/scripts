<#
.SYNOPSIS
Finds Entra ID users who are NOT members of the specified group and exports them to a CSV file.

.DESCRIPTION
This script connects to Microsoft Graph, retrieves all enabled user accounts,
retrieves the members of the 'DUO-MFA' group, compares the lists,
and outputs the users not found in the group to a CSV file named 'noduo.csv'.

.NOTES
Author: Your Name / AI Assistant
Date:   2023-10-27
Requires: Microsoft.Graph PowerShell module (Users, Groups)
Permissions: User.Read.All, GroupMember.Read.All (Delegated permissions for Graph)
#>

# --- Configuration ---
$targetGroupName = "DUO MFA"
$outputCsvPath = ".\noduo.csv" # Output file in the current directory

# --- Script ---

Write-Host "Attempting to connect to Microsoft Graph..."
# Connect to Microsoft Graph. You might be prompted to log in.
# Scopes define the permissions the script requests.
try {
    Connect-MgGraph -Scopes "User.Read.All", "GroupMember.Read.All", "Group.Read.All" -NoWelcome
    Write-Host "Successfully connected to Microsoft Graph." -ForegroundColor Green
}
catch {
    Write-Error "Failed to connect to Microsoft Graph. Ensure the module is installed and you have internet connectivity. Error: $($_.Exception.Message)"
    return # Exit script if connection fails
}

Write-Host "Getting the target group '$targetGroupName'..."
try {
    # Find the group by its Display Name
    $targetGroup = Get-MgGroup -Filter "DisplayName eq '$targetGroupName'" -Property Id -ErrorAction Stop
    if (-not $targetGroup) {
        Write-Error "Group '$targetGroupName' not found in Entra ID."
        Disconnect-MgGraph
        return
    }
    $targetGroupId = $targetGroup.Id
    Write-Host "Found group '$targetGroupName' with ID: $targetGroupId" -ForegroundColor Green
}
catch {
    Write-Error "Error retrieving group '$targetGroupName'. Error: $($_.Exception.Message)"
    Disconnect-MgGraph
    return
}


Write-Host "Getting members of group '$targetGroupName'..."
$groupMemberIds = @{} # Using a hashtable for faster lookups
try {
    # Get all members of the group. We only care about their IDs for the comparison.
    # We use Invoke-MgGraphRequest for efficient pagination handling for potentially large groups
    $uri = "https://graph.microsoft.com/v1.0/groups/$targetGroupId/members?`$select=id"
    $response = Invoke-MgGraphRequest -Uri $uri -Method GET

    # Process first page
    foreach ($member in $response.value) {
        # Ensure we only add user IDs (though Get-MgGroupMember returns directoryObjects, checking type can be complex via API)
        # For this script, we assume members are primarily users. Add check if needed.
         if (-not $groupMemberIds.ContainsKey($member.id)) {
            $groupMemberIds.Add($member.id, $true)
        }
    }

     # Handle subsequent pages if they exist
    while ($response.'@odata.nextLink') {
        Write-Host "Getting next page of group members..." -ForegroundColor Yellow
        $uri = $response.'@odata.nextLink'
        $response = Invoke-MgGraphRequest -Uri $uri -Method GET
         foreach ($member in $response.value) {
             if (-not $groupMemberIds.ContainsKey($member.id)) {
                $groupMemberIds.Add($member.id, $true)
             }
         }
    }

    $memberCount = $groupMemberIds.Count
    Write-Host "Found $memberCount members in group '$targetGroupName'." -ForegroundColor Green
}
catch {
    Write-Error "Error retrieving members for group '$targetGroupName'. Error: $($_.Exception.Message)"
    Disconnect-MgGraph
    return
}

Write-Host "Getting all enabled users from Entra ID (this may take a while for large tenants)..."
$allUsersNotInGroup = [System.Collections.Generic.List[PSObject]]::new()
try {
    # Get all *enabled* users and select properties needed for output and comparison
    # Using Invoke-MgGraphRequest for efficient pagination handling
    $userUri = "https://graph.microsoft.com/v1.0/users?`$filter=accountEnabled eq true&`$select=id,displayName,userPrincipalName,mail&`$count=true"
    $userResponse = Invoke-MgGraphRequest -Uri $userUri -Method GET -Headers @{'ConsistencyLevel'='eventual'} # Required for count and advanced filters

    $totalUserCount = $userResponse.'@odata.count'
    Write-Host "Total enabled users found: $totalUserCount"

    # Process first page
    foreach ($user in $userResponse.value) {
        # Check if the user ID is NOT in the group members hashtable
        if (-not $groupMemberIds.ContainsKey($user.id)) {
            $allUsersNotInGroup.Add([PSCustomObject]@{
                DisplayName       = $user.displayName
                UserPrincipalName = $user.userPrincipalName
                Mail              = $user.mail
                Id                = $user.id
            })
        }
    }
    $processedCount = $userResponse.value.Count
    Write-Progress -Activity "Processing Users" -Status "Processed $processedCount of $totalUserCount users" -PercentComplete ($processedCount / $totalUserCount * 100)


    # Handle subsequent pages if they exist
    while ($userResponse.'@odata.nextLink') {
        Write-Host "Getting next page of users..." -ForegroundColor Yellow
        $userUri = $userResponse.'@odata.nextLink'
        $userResponse = Invoke-MgGraphRequest -Uri $userUri -Method GET -Headers @{'ConsistencyLevel'='eventual'}
        $currentPageCount = $userResponse.value.Count
        foreach ($user in $userResponse.value) {
             if (-not $groupMemberIds.ContainsKey($user.id)) {
                 $allUsersNotInGroup.Add([PSCustomObject]@{
                    DisplayName       = $user.displayName
                    UserPrincipalName = $user.userPrincipalName
                    Mail              = $user.mail
                    Id                = $user.id
                 })
             }
        }
        $processedCount += $currentPageCount
        Write-Progress -Activity "Processing Users" -Status "Processed $processedCount of $totalUserCount users" -PercentComplete ($processedCount / $totalUserCount * 100)
    }
     Write-Progress -Activity "Processing Users" -Completed


    $notFoundCount = $allUsersNotInGroup.Count
    Write-Host "Identified $notFoundCount enabled users who are NOT in the '$targetGroupName' group." -ForegroundColor Green

}
catch {
    Write-Error "Error retrieving users from Entra ID. Error: $($_.Exception.Message)"
    Disconnect-MgGraph
    return
}


if ($allUsersNotInGroup.Count -gt 0) {
    Write-Host "Exporting list of users not in '$targetGroupName' to '$outputCsvPath'..."
    try {
        $allUsersNotInGroup | Export-Csv -Path $outputCsvPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
        Write-Host "Successfully exported $notFoundCount users to $outputCsvPath" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to export data to CSV. Check path permissions or disk space. Error: $($_.Exception.Message)"
    }
}
else {
    Write-Host "No users found that are outside the '$targetGroupName' group." -ForegroundColor Yellow
}

# Disconnect from Microsoft Graph session
Write-Host "Disconnecting from Microsoft Graph."
Disconnect-MgGraph

Write-Host "Script finished."