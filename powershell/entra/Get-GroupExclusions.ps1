<#
.SYNOPSIS
Finds Entra ID internal users who are NOT members of a user-specified group
and exports them to a dynamically named CSV file, including their last sign-in activity.

.DESCRIPTION
This script connects to Microsoft Graph, prompts the user for a group name,
retrieves all enabled internal (non-guest) user accounts along with their sign-in activity,
retrieves the members of the specified group, compares the lists,
and outputs the users not found in the group to a CSV file named '[GroupName]Exclusions_[Timestamp].csv'.
The output includes DisplayName, UserPrincipalName, Mail, UserType, ID, LastInteractiveSignIn, and LastNonInteractiveSignIn.

.NOTES
Author: Your Name / AI Assistant
Date:   2023-10-28 (Updated 2023-10-28 for sign-in activity)
Requires: Microsoft.Graph PowerShell module (Users, Groups, Identity.SignIns)
Permissions: User.Read.All, GroupMember.Read.All, Group.Read.All, AuditLog.Read.All (Delegated permissions for Graph)
Important: Access to signInActivity typically requires Entra ID P1/P2 licenses for users.
           The sign-in activity properties might be null if no sign-in data is available.
#>

# --- Configuration ---
# $targetGroupName will be prompted
# $outputCsvPath will be generated dynamically

# --- Script ---

Write-Host "Attempting to connect to Microsoft Graph..."
# Connect to Microsoft Graph. You might be prompted to log in.
# Scopes define the permissions the script requests. Added AuditLog.Read.All for signInActivity.
try {
    Connect-MgGraph -Scopes "User.Read.All", "GroupMember.Read.All", "Group.Read.All", "AuditLog.Read.All" -NoWelcome
    Write-Host "Successfully connected to Microsoft Graph." -ForegroundColor Green
}
catch {
    Write-Error "Failed to connect to Microsoft Graph. Ensure the module is installed, you have internet connectivity, and consent to required permissions. Error: $($_.Exception.Message)"
    return # Exit script if connection fails
}

# --- Prompt for Group Name ---
$targetGroupName = Read-Host -Prompt "Enter the exact Display Name of the Entra ID group to compare against (e.g., Contoso-All-Users)"
if ([string]::IsNullOrWhiteSpace($targetGroupName)) {
    Write-Error "Group name cannot be empty. Exiting."
    Disconnect-MgGraph
    return
}
Write-Host "You entered group name: '$targetGroupName'"

# --- Generate Dynamic Output CSV Path ---
$timestamp = Get-Date -Format "yyyyMMddHHmmss"
$safeGroupNameForFile = $targetGroupName -replace '[^a-zA-Z0-9_-]', '_' # Sanitize group name
$outputCsvPath = ".\$($safeGroupNameForFile)Exclusions_$($timestamp).csv"
Write-Host "Output CSV file will be: '$outputCsvPath'"


Write-Host "Getting the target group '$targetGroupName'..."
try {
    $targetGroup = Get-MgGroup -Filter "DisplayName eq '$targetGroupName'" -Property Id -ErrorAction Stop
    if (-not $targetGroup) {
        Write-Error "Group '$targetGroupName' not found in Entra ID. Please check the name and try again."
        Disconnect-MgGraph
        return
    }
    if ($targetGroup.Count -gt 1) {
        Write-Warning "Multiple groups found with the name '$targetGroupName'. Using the first one found: $($targetGroup[0].Id)."
        $targetGroup = $targetGroup[0]
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
    $uri = "https://graph.microsoft.com/v1.0/groups/$targetGroupId/members?`$select=id"
    $response = Invoke-MgGraphRequest -Uri $uri -Method GET

    foreach ($member in $response.value) {
         if (-not $groupMemberIds.ContainsKey($member.id)) {
            $groupMemberIds.Add($member.id, $true)
        }
    }

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

Write-Host "Getting all enabled, internal (non-guest) users and their sign-in activity from Entra ID..."
Write-Host "NOTE: This step may take significantly longer due to fetching sign-in activity for each user." -ForegroundColor Yellow
$allUsersNotInGroup = [System.Collections.Generic.List[PSObject]]::new()
try {
    # Select signInActivity to get last sign-in dates. This requires AuditLog.Read.All permission.
    $userUri = "https://graph.microsoft.com/v1.0/users?`$filter=accountEnabled eq true and userType eq 'Member'&`$select=id,displayName,userPrincipalName,mail,userType,signInActivity&`$count=true"
    $userResponse = Invoke-MgGraphRequest -Uri $userUri -Method GET -Headers @{'ConsistencyLevel'='eventual'}

    $totalUserCount = $userResponse.'@odata.count'
    Write-Host "Total enabled, internal users to process: $totalUserCount"
    $processedCount = 0

    # Function to process a page of users
    Function Process-UserPage {
        param($usersPage)
        foreach ($user in $usersPage) {
            if (-not $groupMemberIds.ContainsKey($user.id)) {
                $lastInteractiveSignIn = $null
                $lastNonInteractiveSignIn = $null

                if ($user.signInActivity) {
                    # Use lastSuccessfulSignInDateTime for interactive, as lastSignInDateTime is deprecated
                    $lastInteractiveSignIn = $user.signInActivity.lastSuccessfulSignInDateTime
                    $lastNonInteractiveSignIn = $user.signInActivity.lastNonInteractiveSignInDateTime
                }

                $allUsersNotInGroup.Add([PSCustomObject]@{
                    DisplayName              = $user.displayName
                    UserPrincipalName        = $user.userPrincipalName
                    Mail                     = $user.mail
                    UserType                 = $user.userType
                    Id                       = $user.id
                    LastInteractiveSignIn    = if ($lastInteractiveSignIn) { ([datetime]$lastInteractiveSignIn).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss') } else { "N/A" }
                    LastNonInteractiveSignIn = if ($lastNonInteractiveSignIn) { ([datetime]$lastNonInteractiveSignIn).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss') } else { "N/A" }
                })
            }
            $script:processedCount++ # Access script-level variable
        }
        Write-Progress -Activity "Processing Users" -Status "Processed $script:processedCount of $totalUserCount internal users" -PercentComplete ([math]::Round($script:processedCount / $totalUserCount * 100, 0))
    }

    # Process first page
    Process-UserPage -usersPage $userResponse.value

    # Handle subsequent pages
    while ($userResponse.'@odata.nextLink') {
        Write-Host "Getting next page of internal users..." -ForegroundColor Cyan
        $userUri = $userResponse.'@odata.nextLink'
        $userResponse = Invoke-MgGraphRequest -Uri $userUri -Method GET -Headers @{'ConsistencyLevel'='eventual'}
        Process-UserPage -usersPage $userResponse.value
    }
    Write-Progress -Activity "Processing Users" -Completed

    $notFoundCount = $allUsersNotInGroup.Count
    Write-Host "Identified $notFoundCount enabled, internal users who are NOT in the '$targetGroupName' group." -ForegroundColor Green
}
catch {
    Write-Error "Error retrieving users or their sign-in activity from Entra ID. Error: $($_.Exception.Message)"
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
    Write-Host "No enabled, internal users found that are outside the '$targetGroupName' group." -ForegroundColor Yellow
}

Write-Host "Disconnecting from Microsoft Graph."
Disconnect-MgGraph

Write-Host "Script finished."