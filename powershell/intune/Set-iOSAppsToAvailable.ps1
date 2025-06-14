# PowerShell Script to Assign All iOS Apps as Available to All Users in Intune
# Prerequisites: Microsoft.Graph module and appropriate permissions

# Connect to Microsoft Graph (if not already connected)
# Connect-MgGraph -Scopes "DeviceManagementApps.ReadWrite.All"

# Get all iOS apps from Intune
Write-Host "Retrieving all iOS apps from Intune..." -ForegroundColor Green
$iOSApps = Get-MgDeviceAppManagementMobileApp | Where-Object {
    $_.AdditionalProperties.'@odata.type' -in @(
        '#microsoft.graph.iosLobApp',
        '#microsoft.graph.iosStoreApp', 
        '#microsoft.graph.iosVppApp'
    )
}

Write-Host "Found $($iOSApps.Count) iOS apps" -ForegroundColor Yellow

if ($iOSApps.Count -eq 0) {
    Write-Host "No iOS apps found. Exiting." -ForegroundColor Red
    exit
}

# Display the apps that will be assigned
Write-Host "`nApps to be assigned:" -ForegroundColor Cyan
$iOSApps | ForEach-Object { Write-Host "  - $($_.DisplayName)" }

# Confirm before proceeding
$confirmation = Read-Host "`nDo you want to assign all these apps as 'Available' to 'All Users'? (y/N)"
if ($confirmation -ne 'y' -and $confirmation -ne 'Y') {
    Write-Host "Operation cancelled." -ForegroundColor Red
    exit
}

# Counter for progress tracking
$counter = 0
$successCount = 0
$errorCount = 0
$errors = @()

# Loop through each iOS app and create assignment
foreach ($app in $iOSApps) {
    $counter++
    Write-Host "`n[$counter/$($iOSApps.Count)] Processing: $($app.DisplayName)" -ForegroundColor White
    
    try {
        # Check if assignment already exists
        $existingAssignments = Get-MgDeviceAppManagementMobileAppAssignment -MobileAppId $app.Id -ErrorAction SilentlyContinue
        
        $allUsersAssignmentExists = $existingAssignments | Where-Object {
            $_.Target.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.allLicensedUsersAssignmentTarget' -and
            $_.Intent -eq 'available'
        }
        
        if ($allUsersAssignmentExists) {
            Write-Host "  ✓ Assignment already exists - skipping" -ForegroundColor Yellow
            $successCount++
            continue
        }
        
        # Create the assignment object
        $assignmentBody = @{
            target = @{
                '@odata.type' = '#microsoft.graph.allLicensedUsersAssignmentTarget'
            }
            intent = 'available'
        }
        
        # Create the assignment
        New-MgDeviceAppManagementMobileAppAssignment -MobileAppId $app.Id -BodyParameter $assignmentBody
        Write-Host "  ✓ Successfully assigned" -ForegroundColor Green
        $successCount++
        
    } catch {
        $errorMessage = "Failed to assign $($app.DisplayName): $($_.Exception.Message)"
        Write-Host "  ✗ $errorMessage" -ForegroundColor Red
        $errors += $errorMessage
        $errorCount++
    }
    
    # Small delay to avoid throttling
    Start-Sleep -Milliseconds 500
}

# Summary
Write-Host "`n" + "="*60 -ForegroundColor Cyan
Write-Host "ASSIGNMENT SUMMARY" -ForegroundColor Cyan
Write-Host "="*60 -ForegroundColor Cyan
Write-Host "Total iOS apps processed: $($iOSApps.Count)" -ForegroundColor White
Write-Host "Successfully assigned: $successCount" -ForegroundColor Green
Write-Host "Errors encountered: $errorCount" -ForegroundColor Red

if ($errors.Count -gt 0) {
    Write-Host "`nErrors encountered:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
}

Write-Host "`nScript completed!" -ForegroundColor Green