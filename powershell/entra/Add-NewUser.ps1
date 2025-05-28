<#
.SYNOPSIS
    Creates and sets up a new user in Microsoft 365 and Active Directory (Entra ID).
.DESCRIPTION
    Run with -TestMode to simulate user creation without making changes.

    This script prompts for new user details, creates the user in Microsoft 365,
    sets the password, adds the user to specified groups (including the licensing group),
    waits indefinitely for mailbox provisioning, updates their attributes in Entra ID
    (skipping blank values), and adds them to the "All Employees" Exchange DL.
    It confirms the Display Name and UPN with the user, stripping the domain if
    accidentally entered for the UPN, and re-checks UPN uniqueness upon confirmation.
    It also displays module connection status at the beginning, provides formatted quick
    access links at the end, and times the execution.
.NOTES
    Requires the Microsoft Graph PowerShell SDK and Exchange Online PowerShell Module.
    Ensure you are connected to both before running this script.
#>
param(
    [Switch]$TestMode
)

# --- Start Timer ---
$ScriptStartTime = Get-Date

# --- Module Connection Status ---
Write-Host "--- Module Connection Status ---"
$GraphConnected = $false
try {
    Write-Host "Connecting to Microsoft Graph..."
    Connect-MgGraph -Scopes "User.ReadWrite.All", "Group.Read.All", "GroupMember.ReadWrite.All" -ErrorAction Stop
    Write-Host "Microsoft.Graph - OK"
    $GraphConnected = $true
} catch {
    Write-Error "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
    exit 1
}

$ExchangeOnlineConnected = $false
try {
    Write-Host "Connecting to Exchange Online..."
    Connect-ExchangeOnline -ErrorAction Stop
    Write-Host "ExchangeOnlineManagement - OK"
    $ExchangeOnlineConnected = $true
} catch {
    Write-Warning "Failed to connect to Exchange Online: $($_.Exception.Message)"
}
Write-Host "-----------------------------"

if (-not $GraphConnected) {
    Write-Error "Unable to proceed as connection to Microsoft Graph failed."
    exit 1
}

# --- Prompt for First and Last Name ---
$FirstName = Read-Host "Enter First Name"
$LastName = Read-Host "Enter Last Name"

# --- Confirm Display Name ---
$DisplayName = "$FirstName $LastName"
do {
    Write-Host "Proposed Display Name: '$DisplayName'"
    $ConfirmDisplayName = Read-Host "Is this correct? (Y/N)"
    if ($ConfirmDisplayName.ToUpper() -eq "N") {
        $DisplayName = Read-Host "Enter the desired Display Name"
    } elseif ($ConfirmDisplayName.ToUpper() -ne "Y") {
        Write-Warning "Invalid input. Please enter 'Y' or 'N'."
    }
} while ($ConfirmDisplayName.ToUpper() -ne "Y")
Write-Host "Using Display Name: '$DisplayName'"

# --- Generate Initial User Principal Name (UPN) ---
$InitialUPNPrefix = "$($FirstName[0])$LastName".ToLower()
$UPNDomain = "shippers-supply.com"
$UPNPrefix = $InitialUPNPrefix
$UPN = "$UPNPrefix@$UPNDomain"

# --- Confirm UPN ---
do {
    Write-Host "Proposed User Principal Name: '$UPN'"
    $ConfirmUPN = Read-Host "Is this correct? (Y/N)"
    if ($ConfirmUPN.ToUpper() -eq "Y") {
        # --- Check for UPN uniqueness on confirmation ---
        if (Get-MgUser -Filter "userPrincipalName eq '$UPN'") {
            Write-Warning "The User Principal Name '$UPN' already exists. Please enter a different one."
            $ConfirmUPN = "N" # Force the loop to continue
        }
    } elseif ($ConfirmUPN.ToUpper() -eq "N") {
        $NewUPNInput = Read-Host "Enter the desired username (before @$UPNDomain)"
        if (-not [string]::IsNullOrWhiteSpace($NewUPNInput)) {
            # Strip off the domain if accidentally entered
            $UPNPrefix = $NewUPNInput.ToLower().Replace("@$UPNDomain", "")
            $UPN = "$UPNPrefix@$UPNDomain"
        } else {
            Write-Warning "No new username provided. Please confirm or enter a new one."
        }
    } else {
        Write-Warning "Invalid input. Please enter 'Y' or 'N'."
    }
} while ($ConfirmUPN.ToUpper() -ne "Y")
Write-Host "Using User Principal Name: '$UPN'"

# --- Prompt for Remaining User Details ---
$Title = Read-Host "Enter Title"
$Department = Read-Host "Enter Department"
$MobilePhone = Read-Host "Enter Mobile Phone"

# --- Prompt for Password (Plain String) ---
$Password = Read-Host -Prompt "Enter Temporary Password"

# --- Query and Select Printer Group ---
Write-Host "--- Select Printer Group ---"
$PrinterGroups = Get-MgGroup -Filter "startswith(displayName, 'Printer')" -All
if ($PrinterGroups.Count -gt 0) {
    for ($i = 0; $i -lt $PrinterGroups.Count; $i++) {
        Write-Host "$($i+1). $($PrinterGroups[$i].DisplayName)"
    }
    $Selection = Read-Host "Select the number of the Printer Group (or press Enter to skip)"
    if ($Selection) {
        if ($Selection -as [int] -gt 0 -and $Selection -as [int] -le $PrinterGroups.Count) {
            $SelectedPrinterGroup = $PrinterGroups[$Selection -1]
            Write-Host "Selected Printer Group: $($SelectedPrinterGroup.DisplayName)"
        } else {
            Write-Warning "Invalid printer group selection."
            $SelectedPrinterGroup = $null
        }
    } else {
        Write-Host "Skipping printer group selection."
        $SelectedPrinterGroup = $null
    }
} else {
    Write-Warning "No printer groups found starting with 'Printer'."
    $SelectedPrinterGroup = $null
}

# --- Define Groups to Add (by Display Name) ---
$M365GroupsToAdd = @(
    "All Company Team",
    "DUO MFA",
    "OneDrive Folder Redirect", # This group assigns the license
    "Shippers All Staff"
)

# --- Get the Exchange Distribution List ---
$ExchangeDLName = "All Employees"
$AllEmployeesDL = $null
try {
    if ($ExchangeOnlineConnected) {
        $AllEmployeesDL = Get-DistributionGroup -Filter "DisplayName -eq '$ExchangeDLName'" -ErrorAction Stop
        if (-not $AllEmployeesDL) {
            Write-Warning "Could not find Exchange Distribution List '$ExchangeDLName' by display name."
        } else {
            Write-Host "Found Exchange Distribution List: $($AllEmployeesDL.Name)"
        }
    } else {
        Write-Warning "Skipping Exchange DL check as connection failed."
    }
} catch {
    Write-Warning "Error occurred while trying to find Exchange Distribution List '$ExchangeDLName'."
}

# --- Create New User in Microsoft 365 ---
Write-Host "--- Creating User in Microsoft 365 ---"
if ($TestMode) {
    Write-Host "[TEST MODE] Would create user '$DisplayName' with UPN '$UPN' and set a temporary password."
    $NewUser = New-Object PSObject -Property @{ Id = "test-user-id"; UserPrincipalName = $UPN; DisplayName = $DisplayName } # Mock user object for testing
    $NewUserId = $NewUser.Id
} else {
    try {
        $PasswordProfile = @{
            Password = $Password
            ForceChangePasswordNextSignIn = $false
        }
        $NewUser = New-MgUser -DisplayName $DisplayName -UserPrincipalName $UPN -MailNickname $UPNPrefix -AccountEnabled:$true -PasswordProfile $PasswordProfile
        Write-Host "User '$($NewUser.DisplayName)' created with User Principal Name: $($NewUser.UserPrincipalName), ID: $($NewUser.Id)."
        $NewUserId = $NewUser.Id
    } catch {
        Write-Error "Error creating user: $($_.Exception.Message)"
        exit 1
    }
}

if ($NewUserId) {
    # --- Add User to Microsoft 365 Groups (including licensing group) ---
    Write-Host "--- Adding User to Microsoft 365 Groups (Initial) ---"
    foreach ($GroupName in $M365GroupsToAdd) {
        try {
            $Group = Get-MgGroup -Filter "displayName eq '$GroupName'"
            if ($Group) {
                if ($TestMode) {
                    Write-Host "[TEST MODE] Would add user to group: $($GroupName) (ID: $($Group.Id))"
                } else {
                    New-MgGroupMember -GroupId $Group.Id -DirectoryObjectId $NewUserId
                    Write-Host "Added user to group: $($GroupName)"
                }
            } else {
                Write-Warning "Microsoft 365 Group '$GroupName' not found."
            }
        } catch {
            Write-Error "Error adding user to group '$GroupName': $($_.Exception.Message)"
        }
    }

    # --- Wait Indefinitely for Mailbox Provisioning ---
    $MailboxReady = $false
    Write-Host "--- Waiting indefinitely for mailbox to be provisioned ---"
    while (-not $MailboxReady -and -not $TestMode) {
        Start-Sleep -Seconds 15
        Write-Host "Checking if mailbox exists..."
        try {
            if (Get-Mailbox -Identity $UPN -ErrorAction SilentlyContinue) {
                Write-Host "Mailbox provisioned successfully."
                $MailboxReady = $true
            }
        } catch {
            Write-Warning "Error checking mailbox status: $($_.Exception.Message)"
        }
    }
    if ($TestMode) {
        $MailboxReady = $true # Skip waiting in test mode
    }
    if (-not $MailboxReady -and -not $TestMode) {
        Write-Warning "Mailbox provisioning did not complete within a reasonable time."
    }

    # --- Add User to Selected Printer Group ---
    if ($SelectedPrinterGroup) {
        Write-Host "--- Adding User to Printer Group: $($SelectedPrinterGroup.DisplayName) ---"
        if ($TestMode) {
            Write-Host "[TEST MODE] Would add user to printer group '$($SelectedPrinterGroup.DisplayName)' (ID: $($SelectedPrinterGroup.Id))."
        } else {
            try {
                New-MgGroupMember -GroupId $SelectedPrinterGroup.Id -DirectoryObjectId $NewUserId
                Write-Host "Added user to group: $($SelectedPrinterGroup.DisplayName)"
            } catch {
                Write-Error "Error adding user to printer group '$($SelectedPrinterGroup.DisplayName)': $($_.Exception.Message)"
            }
        }
    }

    # --- Update User Attributes in Entra ID (Skip if Blank) ---
    Write-Host "--- Updating User Attributes in Entra ID ---"
    $userPropertiesToUpdate = @{}
    if (-not [string]::IsNullOrWhiteSpace($Title)) {
        $userPropertiesToUpdate.Add("JobTitle", $Title)
    }
    if (-not [string]::IsNullOrWhiteSpace($Department)) {
        $userPropertiesToUpdate.Add("Department", $Department)
    }
    if (-not [string]::IsNullOrWhiteSpace($MobilePhone)) {
        $userPropertiesToUpdate.Add("MobilePhone", $MobilePhone)
    }
    if ($userPropertiesToUpdate.Count -gt 0 -and -not $TestMode) {
        try {
            Update-MgUser -UserId $NewUserId -BodyParameter $userPropertiesToUpdate
            Write-Host "Updated user attributes."
        } catch {
            Write-Error "Error updating user attributes: $($_.Exception.Message)"
        }
    } elseif ($TestMode -and $userPropertiesToUpdate.Count -gt 0) {
        Write-Host "[TEST MODE] Would update user attributes: $($userPropertiesToUpdate | Out-String)"
    } else {
        Write-Host "No user attributes to update or in Test Mode."
    }

    # --- Add a short delay before adding to Exchange DL ---
    Write-Host "--- Waiting 10 seconds before adding to Exchange DL ---"
    Start-Sleep -Seconds 10

    # --- Add User to Exchange Distribution List ---
    if ($AllEmployeesDL -and $MailboxReady -or $TestMode) {
        Write-Host "--- Adding User to Exchange Distribution List: $($AllEmployeesDL.Name) ---"
        if ($TestMode) {
            Write-Host "[TEST MODE] Would add user with UPN '$UPN' to Exchange DL '$($AllEmployeesDL.PrimarySmtpAddress)'."
        } else {
            try {
                Add-DistributionGroupMember -Identity $AllEmployeesDL.PrimarySmtpAddress -Member $UPN -ErrorAction Stop
                Write-Host "Added user to Exchange Distribution List '$($AllEmployeesDL.Name)'."
            } catch {
                Write-Error "Error adding user to Exchange Distribution List '$($AllEmployeesDL.Name)': $($_.Exception.Message)"
            }
        }
    } elseif (-not $AllEmployeesDL) {
        Write-Warning "Skipping adding user to Exchange DL as the DL was not found."
    } elseif (-not $MailboxReady -and -not $TestMode) {
        Write-Warning "Skipping adding user to Exchange DL as the mailbox was not confirmed."
    }
} else {
    Write-Warning "Unable to proceed with user creation due to connection issues."
}

# --- Stop Timer ---
$ScriptEndTime = Get-Date
$TimeTaken = $ScriptEndTime - $ScriptStartTime

# --- Disconnect from Modules ---
Write-Host "--- Disconnecting from PowerShell Modules ---"
try {
    Disconnect-MgGraph
    Write-Host "Disconnected from Microsoft Graph."
} catch {
    Write-Warning "Error during Microsoft Graph disconnection: $($_.Exception.Message)"
}

try {
    Disconnect-ExchangeOnline
    Write-Host "Disconnected from Exchange Online."
} catch {
    Write-Warning "Error during Exchange Online disconnection: $($_.Exception.Message)"
}

Write-Host "--- Script complete. (Time taken: $($TimeTaken.ToString('c'))) ---"
if ($NewUserId) {
    Write-Host "--- Quick Access Links ---"
    Write-Host
    Write-Host "Microsoft 365 Admin Center:"
    Write-Host "  User Details: https://admin.microsoft.com/Adminportal/Home#/users/:/UserDetails/$NewUserId"
    Write-Host
    Write-Host "Entra Admin Center:"
    Write-Host "  User Overview: https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/overview/userId/$NewUserId/hidePreviewBanner~/true"
    Write-Host
    Write-Host "Microsoft Exchange Admin Center:"
    Write-Host "  Mailbox Details: https://admin.exchange.microsoft.com/#/mailboxes/:/MailboxDetails/$NewUserId"
    Write-Host
    Write-Host "Azure AD Portal:"
    Write-Host "  User Overview: https://aad.portal.azure.com/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/overview/userId/$NewUserId/hidePreviewBanner~/true"
    Write-Host "--------------------------"
}