<#
.SYNOPSIS
    Creates and sets up a new user in Microsoft 365/Entra ID, ensuring license + group assignment occurs before waiting for mailbox provisioning.
.DESCRIPTION
    Run with -TestMode to simulate all operations without making tenant changes.

    1. Prompt for First Name, Last Name, and other attributes.
    2. Auto‐concatenate DisplayName as "FirstName LastName".
    3. Check that the appropriate license SKU (O365_BUSINESS_PREMIUM or SPB) has available seats; abort if none remain.
    4. Create the user via New-MgUser (including required -MailNickname).
    5. Immediately set UsageLocation="US".
    6. Assign license (direct or via group) and add user to all required groups.
    7. Wait for the Exchange mailbox to appear before adding to the “All Employees” DL.
    8. Update any remaining Entra ID attributes (JobTitle, Department, MobilePhone).
.NOTES
    • Requires Microsoft.Graph PowerShell SDK and ExchangeOnlineManagement modules.
    • DisplayName is generated automatically per Graph recommendations.
    • If any required SKU has zero available licenses, the script aborts before creating the user.
#>

param (
    [switch]$TestMode
)

# --- Start Timer ---
$ScriptStartTime = Get-Date

# --- Load + Connect Modules ---
Write-Host "--- Checking for Required Modules and Connections ---"
$GraphConnected          = $false
$ExchangeOnlineConnected = $false

try {
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
        Write-Host "Installing Microsoft.Graph module..."
        Install-Module -Name Microsoft.Graph -Scope CurrentUser -Force
    }
    Write-Host "Connecting to Microsoft Graph..."
    Import-Module Microsoft.Graph
    Connect-MgGraph -Verbose -Scopes "User.ReadWrite.All","Group.Read.All","GroupMember.ReadWrite.All","Organization.Read.All" -ErrorAction Stop
    Write-Host "Connected to Microsoft Graph." 
    $GraphConnected = $true
} catch {
    Write-Error "Unable to connect to Microsoft Graph: $($_.Exception.Message). Exiting."
    exit 1
}

try {
    if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
        Write-Host "Installing ExchangeOnlineManagement module..."
        Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser -Force
    }
    Write-Host "Connecting to Exchange Online..."
    Import-Module ExchangeOnlineManagement
    Connect-ExchangeOnline -ErrorAction Stop
    Write-Host "Connected to Exchange Online."
    $ExchangeOnlineConnected = $true
} catch {
    Write-Warning "Unable to connect to Exchange Online: $($_.Exception.Message). Skipping DL steps."
}

# --- Prompt for Core User Details ---
$FirstName  = Read-Host "Enter First Name"
$LastName   = Read-Host "Enter Last Name"

# Automatically build DisplayName from First + Last
$DisplayName = "$FirstName $LastName"
Write-Host "DisplayName set to: '$DisplayName'"

# Generate UPN prefix and mailNickname (≤64 chars)
$UPNPrefix    = ("$($FirstName[0])$LastName").ToLower()
$UPNDomain    = "shippers-supply.com"
$UPN          = "$UPNPrefix@$UPNDomain"
$MailNickname = $UPNPrefix

do {
    Write-Host "Proposed UPN: '$UPN'"
    $ConfirmUPN = Read-Host "Is this correct? (Y/N)"
    if ($ConfirmUPN.ToUpper() -eq "Y") {
        if (Get-MgUser -Filter "userPrincipalName eq '$UPN'") {
            Write-Warning "The UPN '$UPN' already exists. Please choose another."
            $ConfirmUPN = "N"
        }
    } elseif ($ConfirmUPN.ToUpper() -eq "N") {
        $NewUPNInput = Read-Host "Enter desired username (before '@$UPNDomain')"
        if (-not [string]::IsNullOrWhiteSpace($NewUPNInput)) {
            $UPNPrefix   = $NewUPNInput.ToLower().Replace("@$UPNDomain","")
            $UPN         = "$UPNPrefix@$UPNDomain"
            $MailNickname = $UPNPrefix
        } else {
            Write-Warning "No username provided. Please confirm or enter a new one."
        }
    } else {
        Write-Warning "Invalid input. Please enter 'Y' or 'N'."
    }
} while ($ConfirmUPN.ToUpper() -ne "Y")

Write-Host "Using UPN: '$UPN' and mailNickname: '$MailNickname'"

$Password    = Read-Host "Enter Temporary Password" -AsSecureString
$Title       = Read-Host "Enter Job Title"
$Department  = Read-Host "Enter Department"
$MobilePhone = Read-Host "Enter Mobile Phone Number (optional)"

# --- Determine Required License SKU ---
if ($Department -in @('Warehouse','Production')) {
    # Non-computer users get O365_BUSINESS_PREMIUM directly
    $LicensePartNumber = "O365_BUSINESS_PREMIUM"
    Write-Host "Department '$Department' → will require SKU 'O365_BUSINESS_PREMIUM'."
} else {
    # Computer users receive SPB via group-based licensing (OneDrive Folder Redirect)
    $LicensePartNumber = "SPB"
    Write-Host "Department '$Department' → will require SKU 'SPB' (Microsoft 365 Business Premium)."
}

# --- Check License Availability Before Any Tenant Writes ---
try {
    if ($TestMode) {
        Write-Host "[TEST MODE] Simulating license check for SKU '$LicensePartNumber'."
        $AvailableLicenses = 1
        Write-Host "[TEST MODE] Simulated AvailableLicenses = $AvailableLicenses."
    } else {
        $AllSkus        = Get-MgSubscribedSku -All
        $TargetSkuObj   = $AllSkus | Where-Object { $_.SkuPartNumber -eq $LicensePartNumber }
        if (-not $TargetSkuObj) {
            Write-Error "SKU '$LicensePartNumber' not found in tenant. Exiting."
            exit 1
        }
        $TotalPurchased    = $TargetSkuObj.PrepaidUnits.Enabled
        $TotalConsumed     = $TargetSkuObj.ConsumedUnits
        $AvailableLicenses = $TotalPurchased - $TotalConsumed
        Write-Host "Found SKU '$LicensePartNumber': Purchased=$TotalPurchased, Consumed=$TotalConsumed, Available=$AvailableLicenses."

        if ($AvailableLicenses -lt 1) {
            Write-Error "No available licenses for SKU '$LicensePartNumber'. Aborting."
            exit 1
        }
    }
} catch {
    Write-Error "Error during license-availability check: $($_.Exception.Message). Exiting."
    exit 1
}

# --- Optional: Select Printer Group ---
$PrinterGroups = Get-MgGroup -Filter "startswith(displayName,'Printer')" -All
if ($PrinterGroups.Count -gt 0) {
    Write-Host "--- Select Printer Group ---"
    for ($i=0; $i -lt $PrinterGroups.Count; $i++) {
        Write-Host "$($i+1). $($PrinterGroups[$i].DisplayName)"
    }
    $Selection = Read-Host "Enter Printer Group number (or press Enter to skip)"
    if ($Selection -as [int] -and $Selection -ge 1 -and $Selection -le $PrinterGroups.Count) {
        $SelectedPrinterGroup = $PrinterGroups[$Selection - 1]
        Write-Host "Selected Printer Group: $($SelectedPrinterGroup.DisplayName)"
    } else {
        Write-Warning "No valid selection; skipping printer group."
        $SelectedPrinterGroup = $null
    }
} else {
    Write-Warning "No Printer groups found; skipping."
    $SelectedPrinterGroup = $null
}

# --- Base Microsoft 365 Groups (All Users) ---
$M365GroupsToAdd = @(
    "All Company Team",
    "DUO MFA",
    "Shippers All Staff"
)

# Computer users get the OneDrive Folder Redirect group to auto‐provision SPB
if (-not ($Department -in @('Warehouse','Production'))) {
    $M365GroupsToAdd += "OneDrive Folder Redirect"
}

# --- Locate Exchange Distribution List ---
$ExchangeDLName = "All Employees"
$AllEmployeesDL = $null
if ($ExchangeOnlineConnected) {
    try {
        $AllEmployeesDL = Get-DistributionGroup -Filter "DisplayName -eq '$ExchangeDLName'" -ErrorAction Stop
        if ($AllEmployeesDL) {
            Write-Host "Found Exchange DL: $($AllEmployeesDL.Name)"
        } else {
            Write-Warning "Exchange DL '$ExchangeDLName' not found."
        }
    } catch {
        Write-Warning "Error locating Exchange DL: $($_.Exception.Message)"
    }
} else {
    Write-Warning "Skipping Exchange DL steps due to connection failure."
}

if ($GraphConnected) {
    # --- Create the New User (including required -MailNickname) ---
    if ($TestMode) {
        Write-Host "[TEST MODE] Would run New-MgUser -DisplayName '$DisplayName' `
                    -UserPrincipalName '$UPN' `
                    -AccountEnabled `
                    -PasswordProfile @{ Password = $Password; ForceChangePasswordNextSignIn = $false } `
                    -MailNickname '$MailNickname'"
        $NewUser   = New-Object PSObject -Property @{ Id = "test-user-id"; UserPrincipalName = $UPN; DisplayName = $DisplayName }
        $NewUserId = $NewUser.Id
    } else {
        try {
            $PasswordProfile = @{
                Password                     = $Password
                ForceChangePasswordNextSignIn = $false
            }
            # Corrected: Use -AccountEnabled as a switch (no "$true" after)
            $NewUser = New-MgUser `
                    -DisplayName       $DisplayName `
                    -UserPrincipalName $UPN `
                    -AccountEnabled `
                    -PasswordProfile   $PasswordProfile `
                    -MailNickname      $MailNickname
            $NewUserId = $NewUser.Id
            Write-Host "Created user '$($NewUser.DisplayName)' (ID: $NewUserId)."
        } catch {
            Write-Error "Error creating user: $($_.Exception.Message). Exiting."
            exit 1
        }
    }


    # --- Immediately Set UsageLocation="US" (Required Before Licensing) ---
    if ($TestMode) {
        Write-Host "[TEST MODE] Would update UsageLocation='US' for user ID $NewUserId."
    } else {
        try {
            Update-MgUser -UserId $NewUserId -UsageLocation "US"
            Write-Host "Set UsageLocation='US' for user ID $NewUserId."
        } catch {
            Write-Error "Failed to set UsageLocation: $($_.Exception.Message). Exiting."
            exit 1
        }
    }

    # --- ASSIGN LICENSE & ADD TO GROUPS BEFORE WAITING FOR MAILBOX ---
    Write-Host "--- Assigning License & Adding to Groups ---"

    # 1. Assign License Directly (Warehouse/Production) OR rely on group (OneDrive Folder Redirect) for computer users
    if ($Department -in @('Warehouse','Production')) {
        Write-Host "Assigning 'O365_BUSINESS_PREMIUM' to non-computer user..."
        if ($TestMode) {
            Write-Host "[TEST MODE] Would assign SKU 'O365_BUSINESS_PREMIUM' to user ID $NewUserId."
        } else {
            try {
                $SkuObj = $AllSkus | Where-Object { $_.SkuPartNumber -eq "O365_BUSINESS_PREMIUM" }
                if ($SkuObj) {
                    $SkuId = $SkuObj.SkuId
                    Set-MgUserLicense -UserId $NewUserId `
                                      -AddLicenses @{ SkuId = $SkuId; DisabledPlans = @() } `
                                      -RemoveLicenses @()
                    Write-Host "Assigned 'O365_BUSINESS_PREMIUM' license."
                } else {
                    Write-Warning "SKU 'O365_BUSINESS_PREMIUM' not found; skipping license assignment."
                }
            } catch {
                Write-Error "Error assigning license: $($_.Exception.Message)"
            }
        }
    } else {
        Write-Host "Computer user: will rely on OneDrive Folder Redirect group for 'SPB' license..."
        # No direct license call; group membership below will auto-provision SPB
    }

    # 2. Add to Printer Group if Selected
    if ($SelectedPrinterGroup) {
        Write-Host "Adding user to Printer Group: $($SelectedPrinterGroup.DisplayName)..."
        if ($TestMode) {
            Write-Host "[TEST MODE] Would add user ID $NewUserId to group ID $($SelectedPrinterGroup.Id)."
        } else {
            try {
                New-MgGroupMember -GroupId $SelectedPrinterGroup.Id -DirectoryObjectId $NewUserId
                Write-Host "Added to printer group."
            } catch {
                Write-Error "Error adding to printer group: $($_.Exception.Message)"
            }
        }
    }

    # 3. Add to Base Microsoft 365 Groups (Including OneDrive Folder Redirect if applicable)
    foreach ($GroupName in $M365GroupsToAdd) {
        try {
            $Group = Get-MgGroup -Filter "displayName eq '$GroupName'"
            if ($Group) {
                if ($TestMode) {
                    Write-Host "[TEST MODE] Would add user ID $NewUserId to group '$GroupName' (ID: $($Group.Id))."
                } else {
                    New-MgGroupMember -GroupId $Group.Id -DirectoryObjectId $NewUserId
                    Write-Host "Added to group: $GroupName."
                }
            } else {
                Write-Warning "Group '$GroupName' not found; skipping."
            }
        } catch {
            Write-Error "Error adding to group '$GroupName': $($_.Exception.Message)"
        }
    }

    # --- WAIT FOR MAILBOX TO PROVISION AFTER LICENSE/GROUPS ASSIGNED ---
    Write-Host "--- Waiting for Exchange mailbox to provision ---"
    $MailboxReady = $false
    while (-not $MailboxReady -and -not $TestMode) {
        Start-Sleep -Seconds 15
        try {
            if (Get-Mailbox -Identity $UPN -ErrorAction SilentlyContinue) {
                Write-Host "Mailbox provisioned."
                $MailboxReady = $true
            }
        } catch {
            Write-Warning "Error checking mailbox: $($_.Exception.Message)"
        }
    }
    if ($TestMode) { 
        $MailboxReady = $true 
    } elseif (-not $MailboxReady) {
        Write-Warning "Mailbox still not provisioned after waiting. Continuing without DL addition."
    }

    # --- Add to Exchange Distribution List if mailbox ready ---
    if ($AllEmployeesDL -and $MailboxReady) {
        Write-Host "Adding user to Exchange DL: $($AllEmployeesDL.Name)..."
        if ($TestMode) {
            Write-Host "[TEST MODE] Would add UPN '$UPN' to DL '$($AllEmployeesDL.PrimarySmtpAddress)'."
        } else {
            try {
                Add-DistributionGroupMember -Identity $AllEmployeesDL.PrimarySmtpAddress -Member $UPN -ErrorAction Stop
                Write-Host "Added to Exchange DL."
            } catch {
                Write-Error "Error adding to Exchange DL: $($_.Exception.Message)"
            }
        }
    }

    # --- Update Additional Entra ID Attributes (Skip blanks) ---
    Write-Host "--- Updating user attributes in Entra ID ---"
    $userProps = @{}
    if (-not [string]::IsNullOrWhiteSpace($Title))      { $userProps.Add("JobTitle",$Title) }
    if (-not [string]::IsNullOrWhiteSpace($Department)) { $userProps.Add("Department",$Department) }
    if (-not [string]::IsNullOrWhiteSpace($MobilePhone)){ $userProps.Add("MobilePhone",$MobilePhone) }

    if ($userProps.Count -gt 0) {
        if ($TestMode) {
            Write-Host "[TEST MODE] Would update user ID $NewUserId with: $($userProps | Out-String)."
        } else {
            try {
                Update-MgUser -UserId $NewUserId -BodyParameter $userProps
                Write-Host "Updated additional attributes."
            } catch {
                Write-Error "Error updating attributes: $($_.Exception.Message)"
            }
        }
    }

    # --- Stop Timer + Disconnect ---
    $ScriptEndTime = Get-Date
    $Elapsed       = $ScriptEndTime - $ScriptStartTime

    Write-Host "--- Disconnecting from services ---"
    try {
        Disconnect-MgGraph
        Write-Host "Disconnected from Microsoft Graph."
    } catch {
        Write-Warning "Error disconnecting Graph: $($_.Exception.Message)"
    }
    try {
        if ($ExchangeOnlineConnected) {
            Disconnect-ExchangeOnline -Confirm:$false
            Write-Host "Disconnected from Exchange Online."
        }
    } catch {
        Write-Warning "Error disconnecting Exchange: $($_.Exception.Message)"
    }

    Write-Host "Script completed in $([math]::Round($Elapsed.TotalSeconds,2)) seconds."
} else {
    Write-Warning "Graph connection unavailable; cannot proceed."
}
# Add to Company Directory
$Add-NewUser-CompanyDirectory = Join-Path $PSScriptRoot 'Add-NewUser-CompanyDirectory.ps1'
& $Add-NewUser-CompanyDirectory -UserPrincipalName $


Write-Host "--- Script complete. ---"
if ($NewUserId) {
    $Add-NewUser-LinkWindow = Join-Path $PSScriptRoot 'Add-NewUser-LinkWindow.ps1'
    & $Add-NewUser-LinkWindow -NewUserId $NewUserId
}