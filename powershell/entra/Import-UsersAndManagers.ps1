# AzureAD-Import.ps1 - Simple script that runs when executed
# This script imports manager and department updates from the edited CSV

#Requires -Modules Microsoft.Graph.Users

Write-Host "Starting Azure AD Manager & Department Import..." -ForegroundColor Green

# Check if CSV exists
$csvPath = "./AzureAD_Users_Managers.csv"
if (-not (Test-Path $csvPath)) {
    Write-Error "❌ CSV file not found: $csvPath"
    Write-Host "Make sure you've run the export script first and the CSV file is in the same folder."
    exit
}

# Connect to Microsoft Graph
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
Connect-MgGraph -Scopes "User.ReadWrite.All", "Directory.ReadWrite.All"

# Import CSV
Write-Host "Loading CSV data..." -ForegroundColor Yellow
$userData = Import-Csv -Path $csvPath

# Filter users that need updates
$usersToUpdate = $userData | Where-Object { $_.Action -eq "Update" }
$usersToRemove = $userData | Where-Object { $_.Action -eq "Remove" }

Write-Host "📊 Found:" -ForegroundColor Cyan
Write-Host "  - $($usersToUpdate.Count) users to update (manager/department)" -ForegroundColor Cyan
Write-Host "  - $($usersToRemove.Count) managers to remove" -ForegroundColor Cyan

if ($usersToUpdate.Count -eq 0 -and $usersToRemove.Count -eq 0) {
    Write-Host "❌ No users marked for update or removal. Check your CSV 'Action' column." -ForegroundColor Red
    Disconnect-MgGraph
    exit
}

$successCount = 0
$errorCount = 0

# Process manager updates
Write-Host "`n🔄 Processing user updates..." -ForegroundColor Green
foreach ($user in $usersToUpdate) {
    try {
        $updateParams = @{}
        $updates = @()
        
        # Check if manager needs updating
        if (-not [string]::IsNullOrWhiteSpace($user.NewManagerUPN) -and $user.NewManagerUPN -ne $user.CurrentManagerUPN) {
            # Find new manager
            $newManager = Get-MgUser -Filter "userPrincipalName eq '$($user.NewManagerUPN)'" -Property "Id"
            
            if (-not $newManager) {
                Write-Error "❌ Manager not found: $($user.NewManagerUPN) for user $($user.UserPrincipalName)"
                $errorCount++
                continue
            }
            
            # Set manager reference
            $managerRef = @{
                "@odata.id" = "https://graph.microsoft.com/v1.0/users/$($newManager.Id)"
            }
            
            Set-MgUserManagerByRef -UserId $user.UserObjectId -BodyParameter $managerRef
            $updates += "Manager: $($user.NewManagerUPN)"
        }
        
        # Check if department needs updating
        if (-not [string]::IsNullOrWhiteSpace($user.NewDepartment) -and $user.NewDepartment -ne $user.CurrentDepartment) {
            $updateParams['Department'] = $user.NewDepartment
            $updates += "Department: $($user.NewDepartment)"
        }
        
        # Update user properties if needed
        if ($updateParams.Count -gt 0) {
            Update-MgUser -UserId $user.UserObjectId -BodyParameter $updateParams
        }
        
        if ($updates.Count -gt 0) {
            Write-Host "✅ $($user.UserPrincipalName) → $($updates -join ', ')" -ForegroundColor Green
            $successCount++
        } else {
            Write-Host "ℹ️  $($user.UserPrincipalName) → No changes needed" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Error "❌ Failed to update $($user.UserPrincipalName): $($_.Exception.Message)"
        $errorCount++
    }
}

# Process manager removals
if ($usersToRemove.Count -gt 0) {
    Write-Host "`n🗑️  Processing manager removals..." -ForegroundColor Yellow
    foreach ($user in $usersToRemove) {
        try {
            Remove-MgUserManagerByRef -UserId $user.UserObjectId
            Write-Host "✅ Removed manager for $($user.UserPrincipalName)" -ForegroundColor Green
            $successCount++
        }
        catch {
            Write-Error "❌ Failed to remove manager for $($user.UserPrincipalName): $($_.Exception.Message)"
            $errorCount++
        }
    }
}

# Summary
Write-Host "`n📈 SUMMARY:" -ForegroundColor Cyan
Write-Host "✅ Successful: $successCount" -ForegroundColor Green
Write-Host "❌ Errors: $errorCount" -ForegroundColor Red

# Disconnect
Disconnect-MgGraph

Write-Host "`n🎉 Manager & Department import completed!" -ForegroundColor Green