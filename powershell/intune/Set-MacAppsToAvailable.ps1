# PowerShell Script to Assign macOS Apps as Available to All Users in Intune
# Uses direct Graph API calls to work around PowerShell cmdlet limitations
# Prerequisites: Microsoft.Graph module and appropriate permissions

# Connect to Microsoft Graph (if not already connected)
# Connect-MgGraph -Scopes "DeviceManagementApps.ReadWrite.All"

Write-Host "="*70 -ForegroundColor Cyan
Write-Host "MACOS APP ASSIGNMENT SCRIPT (BETA GRAPH API)" -ForegroundColor Cyan
Write-Host "="*70 -ForegroundColor Cyan

Write-Host "`nNote: Using Microsoft Graph BETA API because macOS apps are only available there" -ForegroundColor Yellow
Write-Host "This explains why standard PowerShell cmdlets don't find macOS apps." -ForegroundColor Gray

# Get all apps using beta Graph API (where macOS apps are available)
Write-Host "`nRetrieving all apps from Intune using beta Graph API..." -ForegroundColor Green
Write-Host "(macOS apps are only available in the beta API endpoint)" -ForegroundColor Gray

try {
    $uri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps"
    $response = Invoke-MgGraphRequest -Method GET -Uri $uri
    $allApps = $response.value
    
    # Handle pagination if needed
    while ($response.'@odata.nextLink') {
        Write-Host "  Retrieving additional pages..." -ForegroundColor Gray
        $response = Invoke-MgGraphRequest -Method GET -Uri $response.'@odata.nextLink'
        $allApps += $response.value
    }
    
    Write-Host "Retrieved $($allApps.Count) total apps from beta API" -ForegroundColor Green
    
} catch {
    Write-Host "Error retrieving apps from beta API: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# Analyze app types
Write-Host "`nAnalyzing app types..." -ForegroundColor Cyan
$appTypes = $allApps | ForEach-Object { $_.'@odata.type' } | Sort-Object | Get-Unique

Write-Host "`nAll app types found:" -ForegroundColor White
$appTypes | ForEach-Object { 
    if ([string]::IsNullOrEmpty($_)) {
        Write-Host "  - (empty/null)" -ForegroundColor Gray
    } else {
        Write-Host "  - $_" 
    }
}

# Look for macOS apps
Write-Host "`nSearching for macOS apps..." -ForegroundColor Cyan
$macOSApps = $allApps | Where-Object {
    $_.'@odata.type' -in @(
        '#microsoft.graph.macOsVppApp',        # Apple VPP apps
        '#microsoft.graph.macOSDmgApp',        # DMG file apps
        '#microsoft.graph.macOSLobApp',        # Line of business apps
        '#microsoft.graph.macOSMicrosoftDefenderApp',
        '#microsoft.graph.macOSMicrosoftEdgeApp',
        '#microsoft.graph.macOSOfficeApp'
    )
}

Write-Host "Found $($macOSApps.Count) macOS apps" -ForegroundColor Yellow

if ($macOSApps.Count -eq 0) {
    Write-Host "`nNo macOS apps found even in beta API." -ForegroundColor Red
    Write-Host "Expected types:" -ForegroundColor Yellow
    Write-Host "  - #microsoft.graph.macOsVppApp (Apple VPP apps)" -ForegroundColor Green
    Write-Host "  - #microsoft.graph.macOSDmgApp (DMG apps)" -ForegroundColor Green
    Write-Host "  - #microsoft.graph.macOSLobApp (Line of business)" -ForegroundColor Green
    Write-Host "`nPlease verify you have macOS apps deployed in Intune." -ForegroundColor Gray
    exit
}

# Display found macOS apps
Write-Host "`nFound macOS apps:" -ForegroundColor White
for ($i = 0; $i -lt $macOSApps.Count; $i++) {
    $app = $macOSApps[$i]
    Write-Host "[$($i+1)] $($app.displayName) - $($app.publisher) ($($app.'@odata.type'))"
}

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

# Loop through each macOS app and create assignment
foreach ($app in $macOSApps) {
    $counter++
    Write-Host "`n[$counter/$($macOSApps.Count)] Processing: $($app.displayName)" -ForegroundColor White
    
    try {
        # Check if assignment already exists using beta API
        $assignmentsUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($app.id)/assignments"
        $existingAssignments = (Invoke-MgGraphRequest -Method GET -Uri $assignmentsUri).value
        
        $allUsersAssignmentExists = $existingAssignments | Where-Object {
            $_.target.'@odata.type' -eq '#microsoft.graph.allLicensedUsersAssignmentTarget' -and
            $_.intent -eq 'available'
        }
        
        if ($allUsersAssignmentExists) {
            Write-Host "  ✓ Assignment already exists - skipping" -ForegroundColor Yellow
            $successCount++
            continue
        }
        
        # Create the assignment using beta API
        $assignmentBody = @{
            target = @{
                '@odata.type' = '#microsoft.graph.allLicensedUsersAssignmentTarget'
            }
            intent = 'available'
        }
        
        $assignUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($app.id)/assignments"
        Invoke-MgGraphRequest -Method POST -Uri $assignUri -Body ($assignmentBody | ConvertTo-Json -Depth 3)
        
        Write-Host "  ✓ Successfully assigned" -ForegroundColor Green
        $successCount++
        
    } catch {
        $errorMessage = "Failed to assign $($app.displayName): $($_.Exception.Message)"
        Write-Host "  ✗ $errorMessage" -ForegroundColor Red
        $errors += $errorMessage
        $errorCount++
    }
    
    # Small delay to avoid throttling
    Start-Sleep -Milliseconds 500
}

# Summary
Write-Host "`n" + "="*60 -ForegroundColor Cyan
Write-Host "MACOS APP ASSIGNMENT SUMMARY" -ForegroundColor Cyan
Write-Host "="*60 -ForegroundColor Cyan
Write-Host "Total macOS apps processed: $($macOSApps.Count)" -ForegroundColor White
Write-Host "Successfully assigned: $successCount" -ForegroundColor Green
Write-Host "Errors encountered: $errorCount" -ForegroundColor Red

if ($errors.Count -gt 0) {
    Write-Host "`nErrors encountered:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
}

Write-Host "`nNOTE: This script uses the Microsoft Graph BETA API because macOS apps" -ForegroundColor Yellow
Write-Host "are only available in the beta endpoint, not the v1.0 API." -ForegroundColor Yellow
Write-Host "This explains why the standard PowerShell cmdlets don't find macOS apps." -ForegroundColor Yellow
Write-Host "`nScript completed!" -ForegroundColor Green