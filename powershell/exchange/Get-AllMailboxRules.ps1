<#
.SYNOPSIS
Retrieves all visible and hidden Inbox rules for all user mailboxes in Exchange Online
and exports the details to a CSV file.

.DESCRIPTION
This script connects to Exchange Online using the ExchangeOnlineManagement module.
It then gets a list of all UserMailboxes. For each mailbox, it retrieves all Inbox
rules, including hidden ones using the -IncludeHidden switch with Get-InboxRule.
The relevant details of each rule are collected and exported to a specified CSV file.

.EXAMPLE
.\Get-AllMailboxRules.ps1 -CsvOutputPath "C:\temp\AllMailboxRules.csv"

This command runs the script and saves the output CSV to C:\temp\AllMailboxRules.csv.

.PARAMETER CsvOutputPath
The full path where the output CSV file should be saved.
#>
param (
    [Parameter(Mandatory=$true)]
    [string]$CsvOutputPath = "C:\temp\ExchangeOnline_MailboxRules.csv" # Default path, change if needed
)

# --- Script Start ---

Write-Host "Attempting to connect to Exchange Online..." -ForegroundColor Yellow

# Connect to Exchange Online (MFA aware)
# You might need to adjust Connect-ExchangeOnline parameters based on your environment
# (e.g., -UserPrincipalName youradmin@yourdomain.com, -Organization yourtenant.onmicrosoft.com)
try {
    # Suppress the connection banner for cleaner output if desired
    Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
    Write-Host "Successfully connected to Exchange Online." -ForegroundColor Green
}
catch {
    Write-Error "Failed to connect to Exchange Online. Please check permissions and ensure the ExchangeOnlineManagement module is installed/updated. Error: $($_.Exception.Message)"
    # Exit the script if connection fails
    Exit 1
}

# Prepare directory for CSV output if it doesn't exist
$CsvDirectory = Split-Path -Path $CsvOutputPath -Parent
if (-not (Test-Path -Path $CsvDirectory)) {
    Write-Host "Creating directory for CSV output: $CsvDirectory" -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $CsvDirectory -Force | Out-Null
}

# Initialize an array to hold the rule data
$allRulesData = @()

Write-Host "Retrieving list of User Mailboxes..." -ForegroundColor Yellow
# Get all User Mailboxes (adjust -Filter if needed for specific types)
# Using -ResultSize Unlimited to ensure all mailboxes are retrieved in larger environments
$mailboxes = Get-Mailbox -ResultSize Unlimited -Filter {RecipientTypeDetails -eq 'UserMailbox'} -ErrorAction SilentlyContinue

if (-not $mailboxes) {
    Write-Warning "No User Mailboxes found or unable to retrieve mailboxes. Exiting."
    Disconnect-ExchangeOnline -Confirm:$false
    Exit 1
}

$totalMailboxes = $mailboxes.Count
$processedCount = 0

Write-Host "Found $totalMailboxes User Mailboxes. Starting rule retrieval..." -ForegroundColor Green
Write-Host "Output will be saved to: $CsvOutputPath"

# Loop through each mailbox
foreach ($mailbox in $mailboxes) {
    $processedCount++
    $mailboxUPN = $mailbox.UserPrincipalName
    $progressPercent = [int](($processedCount / $totalMailboxes) * 100)

    # Display progress
    Write-Progress -Activity "Processing Mailbox Rules" -Status "Checking Mailbox $processedCount of $totalMailboxes : $mailboxUPN" -PercentComplete $progressPercent

    Write-Host "($processedCount/$totalMailboxes) Processing Mailbox: $mailboxUPN" -ForegroundColor Cyan

    try {
        # Get ALL rules (visible and hidden) for the current mailbox
        # Use -ErrorAction SilentlyContinue to handle mailboxes with no rules gracefully
        $rules = Get-InboxRule -Mailbox $mailboxUPN -IncludeHidden -ErrorAction SilentlyContinue

        if ($rules) {
            # Loop through each rule found for this mailbox
            foreach ($rule in $rules) {
                # Create a custom object with the desired properties
                $ruleDetails = [PSCustomObject]@{
                    MailboxOwner      = $mailboxUPN
                    RuleName          = $rule.Name
                    RuleIdentity      = $rule.Identity.ToString() # Unique ID for the rule
                    RulePriority      = $rule.Priority
                    RuleEnabled       = $rule.Enabled
                    RuleDescription   = $rule.Description # Often contains conditions/actions text
                    # Add other properties from $rule if needed, e.g.:
                    # StopProcessingRules = $rule.StopProcessingRules
                    From              = $rule.From -join ';' # Example if 'From' is an array
                    SentTo            = $rule.SentTo -join ';' # Example if 'SentTo' is an array
                    MoveToFolder      = $rule.MoveToFolder # May contain folder path
                    DeleteMessage     = $rule.DeleteMessage
                    ForwardTo         = $rule.ForwardTo -join ';'
                    ForwardAsAttachmentTo = $rule.ForwardAsAttachmentTo -join ';'
                    RedirectTo        = $rule.RedirectTo -join ';'
                }
                # Add the details to our results array
                $allRulesData += $ruleDetails
            }
            Write-Host "  Found $($rules.Count) rule(s) for $mailboxUPN." -ForegroundColor Green
        } else {
            Write-Host "  No rules found for $mailboxUPN."
        }
    }
    catch {
        # Log any errors encountered for a specific mailbox but continue with the next
        Write-Warning "Could not retrieve rules for mailbox $mailboxUPN. Error: $($_.Exception.Message)"
        # Optionally add an entry to the CSV indicating the failure for this mailbox
        $errorDetails = [PSCustomObject]@{
            MailboxOwner      = $mailboxUPN
            RuleName          = "ERROR"
            RuleIdentity      = "N/A"
            RulePriority      = "N/A"
            RuleEnabled       = "N/A"
            RuleDescription   = "Failed to retrieve rules. Error: $($_.Exception.Message)"
        }
        $allRulesData += $errorDetails
    }
}

# Export the collected data to CSV
if ($allRulesData.Count -gt 0) {
    Write-Host "Exporting $($allRulesData.Count) rule entries to $CsvOutputPath..." -ForegroundColor Yellow
    try {
        $allRulesData | Export-Csv -Path $CsvOutputPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
        Write-Host "Successfully exported rules to $CsvOutputPath" -ForegroundColor Green
    } catch {
        Write-Error "Failed to export data to CSV. Error: $($_.Exception.Message)"
        Write-Error "Data count: $($allRulesData.Count). First item example: $($allRulesData[0] | Out-String)"
    }

} else {
    Write-Warning "No rule data was collected. CSV file will not be created."
}

# Disconnect from Exchange Online
Write-Host "Disconnecting from Exchange Online..." -ForegroundColor Yellow
Disconnect-ExchangeOnline -Confirm:$false

Write-Host "Script finished." -ForegroundColor Green