# Comprehensive SharePoint/OneDrive Deletion Monitor
# Captures ALL deletion events for security monitoring

Write-Host "`nSharePoint/OneDrive Deletion Security Monitor" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan

# Step 1: Module check and connection
Write-Host "`n1. Checking PowerShell modules..." -ForegroundColor Green

$RequiredModule = "ExchangeOnlineManagement"
$ModuleInstalled = Get-Module -ListAvailable -Name $RequiredModule

if (-not $ModuleInstalled) {
    Write-Host "   Installing $RequiredModule..." -ForegroundColor Yellow
    Install-Module -Name $RequiredModule -Force -AllowClobber -Scope CurrentUser
}

if (-not (Get-Module $RequiredModule)) {
    Import-Module $RequiredModule -Force
}

# Step 2: Connect to Exchange Online
Write-Host "`n2. Connecting to Exchange Online..." -ForegroundColor Green

try {
    $ExistingConnection = Get-ConnectionInformation -ErrorAction SilentlyContinue
    
    if ($ExistingConnection) {
        Write-Host "   ✓ Already connected as: $($ExistingConnection[0].UserPrincipalName)" -ForegroundColor Green
    } else {
        Connect-ExchangeOnline -ShowProgress $true
        Write-Host "   ✓ Successfully connected" -ForegroundColor Green
    }
} catch {
    Write-Host "   ✗ Failed to connect: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# Step 3: Verify audit logging is enabled
Write-Host "`n3. Verifying audit configuration..." -ForegroundColor Green

try {
    $AuditConfig = Get-AdminAuditLogConfig
    if ($AuditConfig.UnifiedAuditLogIngestionEnabled) {
        Write-Host "   ✓ Unified audit logging is enabled" -ForegroundColor Green
    } else {
        Write-Host "   ! Enabling audit logging..." -ForegroundColor Yellow
        Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled $true
        Write-Host "   ✓ Audit logging enabled" -ForegroundColor Green
    }
} catch {
    Write-Host "   ✗ Could not verify audit config: $($_.Exception.Message)" -ForegroundColor Red
}

# Step 4: Set up search parameters
Write-Host "`n4. Configuring deletion search parameters..." -ForegroundColor Green

# CRITICAL: Use 3-hour buffer for audit log delay
$EndDate = (Get-Date).AddHours(-3)  # Account for 60-90 minute audit delay
$StartDate = $EndDate.AddHours(-48)  # Look back 48 hours from buffer time

Write-Host "   Search window: $($StartDate.ToString('yyyy-MM-dd HH:mm')) to $($EndDate.ToString('yyyy-MM-dd HH:mm'))" -ForegroundColor Yellow
Write-Host "   Note: Using 3-hour buffer to account for audit log ingestion delay" -ForegroundColor Gray

# Complete list of ALL deletion operations
$DeletionOperations = @(
    "FileRecycled",                      # PRIMARY - replaced FileDeleted in 2021
    "FileDeletedFirstStageRecycleBin",   # Permanent deletion from site recycle bin
    "FileDeletedSecondStageRecycleBin",  # Final deletion from site collection recycle bin
    "FileDeleted",                       # Legacy - kept for backward compatibility
    "FileVersionRecycled",               # Individual version deletion
    "FileVersionsAllRecycled",           # All versions deleted
    "FileVersionsAllMinorsRecycled",     # All minor versions deleted
    "FolderRecycled",                    # Folder deletions
    "FolderDeleted",                     # Legacy folder deletions
    "FilePermanentDeleted",              # Direct permanent deletion
    "FileRestored"                       # Track restorations too for context
)

# Step 5: Search with proper pagination
Write-Host "`n5. Searching for ALL deletion events..." -ForegroundColor Green
Write-Host "   This may take several minutes for large datasets..." -ForegroundColor Gray

$SessionId = "DeletionMonitor_" + (Get-Date -Format "yyyyMMddHHmmss")
$AllResults = @()
$PageNumber = 1
$OperationStats = @{}

# Search for each operation type separately for better results
foreach ($Operation in $DeletionOperations) {
    Write-Host "`n   Searching for: $Operation" -ForegroundColor Cyan
    
    $OperationResults = @()
    $HasMoreData = $true
    $SessionCommand = "ReturnLargeSet"
    
    while ($HasMoreData) {
        try {
            $Results = Search-UnifiedAuditLog `
                -StartDate $StartDate `
                -EndDate $EndDate `
                -RecordType SharePointFileOperation `
                -Operations $Operation `
                -SessionId "$SessionId`_$Operation" `
                -SessionCommand $SessionCommand `
                -ResultSize 5000 `
                -ErrorAction Stop
            
            if ($Results -and $Results.Count -gt 0) {
                $OperationResults += $Results
                Write-Host "     Retrieved page $PageNumber`: $($Results.Count) records (Total: $($OperationResults.Count))" -ForegroundColor Gray
                $PageNumber++
                
                # After first call, use ReturnLargeSet for remaining pages
                if ($SessionCommand -eq "ReturnLargeSet" -and $Results.Count -eq 5000) {
                    # Continue pagination
                } else {
                    $HasMoreData = $false
                }
            } else {
                $HasMoreData = $false
            }
            
            # Prevent API throttling
            Start-Sleep -Milliseconds 500
            
        } catch {
            Write-Host "     ⚠ Error: $($_.Exception.Message)" -ForegroundColor Yellow
            $HasMoreData = $false
        }
    }
    
    if ($OperationResults.Count -gt 0) {
        $AllResults += $OperationResults
        $OperationStats[$Operation] = $OperationResults.Count
        Write-Host "     ✓ Found $($OperationResults.Count) $Operation events" -ForegroundColor Green
    } else {
        Write-Host "     ○ No $Operation events found" -ForegroundColor Gray
    }
    
    $PageNumber = 1
}

# Step 6: Process and analyze results
if ($AllResults.Count -gt 0) {
    Write-Host "`n6. Analyzing deletion patterns..." -ForegroundColor Green
    Write-Host "   Total events found: $($AllResults.Count)" -ForegroundColor White
    
    $ProcessedResults = @()
    $SuspiciousActivity = @()
    
    foreach ($Record in $AllResults) {
        try {
            $AuditData = $Record.AuditData | ConvertFrom-Json
            
            # Determine if this is a user or system deletion
            $IsSystemDeletion = $false
            $DeletedBy = $Record.UserIds
            
            if ($Record.UserIds -match "SHAREPOINT\\system|app@sharepoint|\.service@|^S-1-5-18$") {
                $IsSystemDeletion = $true
                if ($AuditData.UserId) { $DeletedBy = $AuditData.UserId }
            }
            
            # Extract file information
            $FileName = if ($AuditData.SourceFileName) { $AuditData.SourceFileName }
                       elseif ($AuditData.ObjectId) { Split-Path $AuditData.ObjectId -Leaf }
                       else { "Unknown" }
            
            $ProcessedRecord = [PSCustomObject]@{
                'Timestamp' = $Record.CreationDate
                'User' = $DeletedBy
                'Operation' = $Record.Operations
                'FileName' = $FileName
                'FilePath' = $AuditData.ObjectId
                'SiteUrl' = $AuditData.SiteUrl
                'SourceRelativeUrl' = $AuditData.SourceRelativeUrl
                'ClientIP' = $AuditData.ClientIP
                'UserAgent' = $AuditData.UserAgent
                'IsSystemDeletion' = $IsSystemDeletion
                'IsExternalUser' = $DeletedBy -like "*#EXT#*"
                'Workload' = $AuditData.Workload
                'EventSource' = $AuditData.EventSource
                'ItemType' = $AuditData.ItemType
            }
            
            $ProcessedResults += $ProcessedRecord
            
            # Flag suspicious patterns
            $Hour = (Get-Date $Record.CreationDate).Hour
            if (-not $IsSystemDeletion -and ($Hour -lt 6 -or $Hour -gt 22)) {
                $ProcessedRecord | Add-Member -NotePropertyName "Flag" -NotePropertyValue "Off-hours deletion"
                $SuspiciousActivity += $ProcessedRecord
            }
            
            if ($ProcessedRecord.IsExternalUser) {
                $ProcessedRecord | Add-Member -NotePropertyName "Flag" -NotePropertyValue "External user deletion" -Force
                $SuspiciousActivity += $ProcessedRecord
            }
            
        } catch {
            Write-Host "   ⚠ Could not parse record: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    
    # Step 7: Generate security analysis
    Write-Host "`n7. Security Analysis Results:" -ForegroundColor Green
    Write-Host ("=" * 60) -ForegroundColor Cyan
    
    # Operation breakdown
    Write-Host "`nDeletion Operations Breakdown:" -ForegroundColor Yellow
    foreach ($Op in $OperationStats.GetEnumerator() | Sort-Object Value -Descending) {
        Write-Host ("   {0,-35} {1,6} events" -f $Op.Key, $Op.Value)
    }
    
    # User analysis
    $UserStats = $ProcessedResults | Where-Object { -not $_.IsSystemDeletion } | 
        Group-Object User | Sort-Object Count -Descending
    
    $SystemStats = $ProcessedResults | Where-Object { $_.IsSystemDeletion } | 
        Group-Object User | Sort-Object Count -Descending
    
    Write-Host "`nTop User Deletions (Non-System):" -ForegroundColor Yellow
    $UserStats | Select-Object -First 10 | ForEach-Object {
        $IsExternal = if ($_.Name -like "*#EXT#*") { " [EXTERNAL]" } else { "" }
        Write-Host ("   {0,-40} {1,6} deletions{2}" -f $_.Name, $_.Count, $IsExternal)
    }
    
    # High-volume detection
    $HighVolumeUsers = $UserStats | Where-Object { $_.Count -gt 15 }
    if ($HighVolumeUsers) {
        Write-Host "`n⚠ HIGH-VOLUME DELETIONS DETECTED:" -ForegroundColor Red
        $HighVolumeUsers | ForEach-Object {
            Write-Host "   $($_.Name): $($_.Count) deletions in 48 hours" -ForegroundColor Red
        }
    }
    
    # Suspicious activity summary
    if ($SuspiciousActivity.Count -gt 0) {
        Write-Host "`n⚠ SUSPICIOUS ACTIVITY FLAGS:" -ForegroundColor Red
        $SuspiciousActivity | Group-Object Flag | ForEach-Object {
            Write-Host "   $($_.Name): $($_.Count) events" -ForegroundColor Red
        }
        
        Write-Host "`n   Recent suspicious deletions:" -ForegroundColor Yellow
        $SuspiciousActivity | Select-Object -First 5 | Format-Table Timestamp, User, FileName, Flag -AutoSize
    }
    
    # Site impact analysis
    Write-Host "`nMost Affected Sites:" -ForegroundColor Yellow
    $ProcessedResults | Where-Object { $_.SiteUrl } | 
        Group-Object SiteUrl | Sort-Object Count -Descending | 
        Select-Object -First 5 | ForEach-Object {
            Write-Host ("   {0,-50} {1,6} deletions" -f $_.Name, $_.Count)
        }
    
    # Export options
    Write-Host "`n8. Export Options:" -ForegroundColor Green
    $ExportPath = "SharePointDeletions_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $ProcessedResults | Export-Csv -Path $ExportPath -NoTypeInformation
    Write-Host "   ✓ Full results exported to: $ExportPath" -ForegroundColor Green
    
    # Security recommendations
    Write-Host "`n9. Security Recommendations:" -ForegroundColor Cyan
    Write-Host "   Based on the analysis:" -ForegroundColor White
    
    if ($HighVolumeUsers) {
        Write-Host "   • URGENT: Investigate high-volume deletion users immediately" -ForegroundColor Red
        Write-Host "   • Consider temporarily restricting these accounts" -ForegroundColor Yellow
    }
    
    if (($ProcessedResults | Where-Object { $_.IsExternalUser }).Count -gt 0) {
        Write-Host "   • Review external user permissions - external users performed deletions" -ForegroundColor Yellow
    }
    
    if (($SuspiciousActivity | Where-Object { $_.Flag -eq "Off-hours deletion" }).Count -gt 10) {
        Write-Host "   • Multiple off-hours deletions detected - verify with users" -ForegroundColor Yellow
    }
    
    Write-Host "   • Enable deletion alerts in Microsoft 365 security center" -ForegroundColor White
    Write-Host "   • Consider implementing DLP policies to prevent mass deletions" -ForegroundColor White
    Write-Host "   • Review and potentially shorten recycle bin retention periods" -ForegroundColor White
    
} else {
    Write-Host "`n6. No deletion events found in the specified timeframe" -ForegroundColor Yellow
    Write-Host "`nPossible reasons:" -ForegroundColor Gray
    Write-Host "   - Audit log ingestion delay (events may appear in 1-3 hours)" -ForegroundColor Gray
    Write-Host "   - No actual deletions occurred in this period" -ForegroundColor Gray
    Write-Host "   - Audit logging was recently enabled" -ForegroundColor Gray
    Write-Host "`nTry extending the search period or checking again later." -ForegroundColor White
}

Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
Write-Host "Scan complete. Connection remains active for further investigation." -ForegroundColor Green
Write-Host "Run 'Disconnect-ExchangeOnline' when finished." -ForegroundColor Yellow