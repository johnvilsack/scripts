<#
.SYNOPSIS
Retrieves all visible and hidden Inbox rules for a specific user mailbox in Exchange Online
and exports the details to a CSV file saved in the script's execution directory.

.DESCRIPTION
This script connects to Exchange Online using the ExchangeOnlineManagement module.
It prompts the user to enter the User Principal Name (email address) of the target mailbox.
It then retrieves all Inbox rules for that specific mailbox, including hidden ones,
using the -IncludeHidden switch with Get-InboxRule.
A comprehensive set of rule details, including a 'RuleVisibility' column,
is collected and exported to a CSV file named 'Rules_[UserAlias].csv'
in the same directory as the script file.

.EXAMPLE
.\Get-SingleUserMailboxRules_LocalOutput.ps1
# The script will prompt you to enter the user's email address.
# The output CSV (e.g., Rules_jdoe.csv) will be saved in the same folder as the .ps1 file.
#>

# --- Script Start ---

# Get the directory where the script itself is located
$ScriptDirectory = $PSScriptRoot

Write-Host "Attempting to connect to Exchange Online..." -ForegroundColor Yellow

# Connect to Exchange Online (MFA aware)
try {
    # Ensure the module is loaded (optional if already loaded in profile)
    Import-Module ExchangeOnlineManagement -ErrorAction Stop
    Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
    Write-Host "Successfully connected to Exchange Online." -ForegroundColor Green
}
catch {
    Write-Error "Failed to connect to Exchange Online. Please check permissions and ensure the ExchangeOnlineManagement module is installed/updated. Error: $($_.Exception.Message)"
    Exit 1
}

# Prompt for the target user's email address
$targetUserUPN = Read-Host "Please enter the User Principal Name (email address) of the target mailbox"

# Basic validation of input
if ([string]::IsNullOrWhiteSpace($targetUserUPN)) {
    Write-Error "No email address entered. Exiting."
    Disconnect-ExchangeOnline -Confirm:$false
    Exit 1
}

$targetUserUPN = $targetUserUPN.Trim() # Remove leading/trailing whitespace

# Validate the mailbox exists
Write-Host "Validating mailbox: $targetUserUPN" -ForegroundColor Yellow
try {
    $targetMailbox = Get-Mailbox -Identity $targetUserUPN -ErrorAction Stop
    Write-Host "Mailbox validated successfully: $($targetMailbox.DisplayName) ($($targetMailbox.Alias))" -ForegroundColor Green
}
catch {
    Write-Error "Failed to find or access mailbox '$targetUserUPN'. Please check the email address and your permissions. Error: $($_.Exception.Message)"
    Disconnect-ExchangeOnline -Confirm:$false
    Exit 1
}

# Construct the final CSV path in the script's directory
$userAlias = $targetMailbox.Alias
$CsvFileName = "Rules_$($userAlias).csv"
$CsvFilePath = Join-Path -Path $ScriptDirectory -ChildPath $CsvFileName

Write-Host "Retrieving rules for mailbox: $targetUserUPN" -ForegroundColor Yellow
Write-Host "Output will be saved to: $CsvFilePath"

# Initialize an array to hold the rule data
$rulesData = @()

try {
    # Get ALL rules (visible and hidden) for the specified mailbox
    $rules = Get-InboxRule -Mailbox $targetUserUPN -IncludeHidden -ErrorAction Stop

    if ($rules) {
        Write-Host "Found $($rules.Count) rule(s) for $targetUserUPN." -ForegroundColor Green
        # Loop through each rule found
        foreach ($rule in $rules) {
            # Determine visibility
            $visibility = if ($rule.IsHidden) { "Hidden" } else { "Visible" }

            # Create a custom object with the desired properties
            $ruleDetails = [PSCustomObject]@{
                MailboxOwner          = $targetUserUPN
                RuleName              = $rule.Name
                RuleVisibility        = $visibility # Added visibility column
                RuleEnabled           = $rule.Enabled
                RulePriority          = $rule.Priority
                RuleIdentity          = $rule.Identity.ToString() # Unique ID for the rule
                RuleDescription       = $rule.Description # Often contains conditions/actions text
                IsHidden              = $rule.IsHidden # Raw boolean value
                StopProcessingRules   = $rule.StopProcessingRules
                From                  = $rule.From -join ';'
                SentTo                = $rule.SentTo -join ';'
                SubjectContainsWords  = $rule.SubjectContainsWords -join ';'
                BodyContainsWords     = $rule.BodyContainsWords -join ';'
                HeaderContainsWords   = $rule.HeaderContainsWords -join ';'
                FromAddressContainsWords = $rule.FromAddressContainsWords -join ';'
                RecipientAddressContainsWords = $rule.RecipientAddressContainsWords -join ';'
                SentToMe              = $rule.SentToMe
                MyNameInToBox         = $rule.MyNameInToBox
                MyNameInCcBox         = $rule.MyNameInCcBox
                MyNameNotInToBox      = $rule.MyNameNotInToBox
                MyNameInToOrCcBox     = $rule.MyNameInToOrCcBox
                HasAttachment         = $rule.HasAttachment
                MessageTypeMatches    = $rule.MessageTypeMatches
                Sensitivity           = $rule.Sensitivity
                WithinSizeRangeMaximum= $rule.WithinSizeRangeMaximum # Often needs conversion if used: $rule.WithinSizeRangeMaximum.ToKB()
                WithinSizeRangeMinimum= $rule.WithinSizeRangeMinimum # Often needs conversion if used: $rule.WithinSizeRangeMinimum.ToKB()
                MoveToFolder          = $rule.MoveToFolder # Folder path string
                CopyToFolder          = $rule.CopyToFolder # Folder path string
                DeleteMessage         = $rule.DeleteMessage
                ForwardTo             = $rule.ForwardTo -join ';'
                ForwardAsAttachmentTo = $rule.ForwardAsAttachmentTo -join ';'
                RedirectTo            = $rule.RedirectTo -join ';'
                MarkImportance        = $rule.MarkImportance
                MarkAsRead            = $rule.MarkAsRead
                ApplyCategory         = $rule.ApplyCategory -join ';'
                # Add any other relevant properties from Get-InboxRule output if needed
            }
            # Add the details to our results array
            $rulesData += $ruleDetails
        }
    } else {
        Write-Host "No rules found for mailbox $targetUserUPN." -ForegroundColor Yellow
    }
}
catch {
    # Log any errors encountered during rule retrieval for this user
    Write-Error "Could not retrieve rules for mailbox $targetUserUPN. Error: $($_.Exception.Message)"
}

# Export the collected data to CSV
if ($rulesData.Count -gt 0) {
    Write-Host "Exporting $($rulesData.Count) rule entries to $CsvFilePath..." -ForegroundColor Yellow
    try {
        $rulesData | Export-Csv -Path $CsvFilePath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
        Write-Host "Successfully exported rules to $CsvFilePath" -ForegroundColor Green
    } catch {
        Write-Error "Failed to export data to CSV. Error: $($_.Exception.Message)"
        Write-Error "Please ensure you have write permissions in the script directory: $ScriptDirectory"
    }
} else {
    Write-Warning "No rule data was collected or an error occurred during retrieval. CSV file '$CsvFilePath' may not be created or may be empty."
}

# Disconnect from Exchange Online
Write-Host "Disconnecting from Exchange Online..." -ForegroundColor Yellow
Disconnect-ExchangeOnline -Confirm:$false

Write-Host "Script finished." -ForegroundColor Green