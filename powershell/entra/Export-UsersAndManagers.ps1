# AzureAD-Export.ps1 - Simple script that runs when executed
# This script exports all users and their managers to CSV

#Requires -Modules Microsoft.Graph.Users

Write-Host "Starting Azure AD User Manager Export..." -ForegroundColor Green

# Connect to Microsoft Graph
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
Connect-MgGraph -Scopes "User.Read.All", "Directory.Read.All"

# Get all users
Write-Host "Retrieving all users..." -ForegroundColor Yellow
$users = Get-MgUser -All -Property "Id,UserPrincipalName,DisplayName,JobTitle,Department,Manager"

Write-Host "Processing $($users.Count) users..." -ForegroundColor Yellow

# Create array for results
$results = @()

foreach ($user in $users) {
    $managerUPN = ""
    $managerDisplayName = ""
    $managerId = ""
    
    # Get manager details if manager exists
    if ($user.Manager.AdditionalProperties.id) {
        try {
            $manager = Get-MgUser -UserId $user.Manager.AdditionalProperties.id -Property "Id,UserPrincipalName,DisplayName"
            $managerUPN = $manager.UserPrincipalName
            $managerDisplayName = $manager.DisplayName
            $managerId = $manager.Id
        }
        catch {
            Write-Warning "Could not get manager for $($user.UserPrincipalName)"
        }
    }
    
    # Add to results
    $results += [PSCustomObject]@{
        UserPrincipalName = $user.UserPrincipalName
        UserDisplayName = $user.DisplayName
        UserObjectId = $user.Id
        CurrentJobTitle = $user.JobTitle
        CurrentDepartment = $user.Department
        CurrentManagerUPN = $managerUPN
        CurrentManagerDisplayName = $managerDisplayName
        CurrentManagerObjectId = $managerId
        NewJobTitle = $user.JobTitle           # Edit this column for title changes
        NewDepartment = $user.Department       # Edit this column for department changes
        NewManagerUPN = $managerUPN            # Edit this column for manager changes
        Action = "NoChange"                    # Change to "Update" or "Remove"
    }
    
    # Show progress
    if ($results.Count % 50 -eq 0) {
        Write-Host "Processed $($results.Count) users..." -ForegroundColor Green
    }
}

# Export to CSV
$csvPath = "./AzureAD_Users_Managers.csv"
$results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

Write-Host "✅ Export completed!" -ForegroundColor Green
Write-Host "📁 File saved: $csvPath" -ForegroundColor Green
Write-Host "👥 Total users: $($results.Count)" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Edit the CSV file" -ForegroundColor Cyan
Write-Host "2. Update 'NewJobTitle' column with new job titles" -ForegroundColor Cyan
Write-Host "3. Update 'NewDepartment' column with new departments" -ForegroundColor Cyan
Write-Host "4. Update 'NewManagerUPN' column with correct managers" -ForegroundColor Cyan
Write-Host "5. Set 'Action' to 'Update' for users to change" -ForegroundColor Cyan
Write-Host "6. Set 'Action' to 'Remove' to remove manager assignment" -ForegroundColor Cyan
Write-Host "7. Run the import script" -ForegroundColor Cyan

# Disconnect
Disconnect-MgGraph

Write-Host "Script completed!" -ForegroundColor Green