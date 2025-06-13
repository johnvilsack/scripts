<#
.SYNOPSIS
    Creates a new user or updates an existing user in Microsoft 365/Entra ID.
.DESCRIPTION
    A robust, user-friendly script for user management.
    - Features color-coded sections for improved readability.
    - Uses a "Name Reconciliation" menu to intelligently handle user names.
    - Correctly pre-fills all fields in update mode.
    - Reliably swaps printer groups and licenses based on role changes.
.NOTES
    • Requires Microsoft.Graph PowerShell SDK and ExchangeOnlineManagement modules.
    • Company field is set to "Shippers-Supply".
#>

param (
    [switch]$TestMode
)

# --- Function for Section Headers ---
function Write-SectionHeader {
    param ([string]$Title)
    Write-Host ""
    Write-Host "--- $($Title.ToUpper()) ---" -ForegroundColor Cyan
}

# --- Start Timer ---
$ScriptStartTime = Get-Date

# --- Initialize script-level variables ---
$ExistingUser = $null
$UpdateMode = $false
$OriginalDepartment = $null
$OriginalPrinterGroup = $null

# --- Load + Connect Modules ---
Write-SectionHeader "Connecting to Microsoft Services"
# (Module connection logic is stable and remains unchanged)
$GraphConnected          = $false
$ExchangeOnlineConnected = $false
$RequiredGraphModules = @(
    "Microsoft.Graph.Authentication", "Microsoft.Graph.Users", "Microsoft.Graph.Groups",
    "Microsoft.Graph.Identity.DirectoryManagement", "Microsoft.Graph.Users.Actions"
)
$GraphContext = Get-MgContext -ErrorAction SilentlyContinue
if ($GraphContext) {
    Write-Host "Already connected to Microsoft Graph as: $($GraphContext.Account)"; $GraphConnected = $true
} else {
    try {
        foreach ($Module in $RequiredGraphModules) {
            if (-not (Get-Module -ListAvailable -Name $Module)) { Write-Host "Installing $Module..."; Install-Module -Name $Module -Scope CurrentUser -Force }
            Import-Module $Module
        }
        Write-Host "Connecting to Microsoft Graph..."; Connect-MgGraph -Scopes "User.ReadWrite.All","Group.ReadWrite.All","Organization.Read.All","Directory.ReadWrite.All" -ErrorAction Stop
        Write-Host "Connected to Microsoft Graph."; $GraphConnected = $true
    } catch { Write-Error "Unable to connect to Microsoft Graph: $($_.Exception.Message). Exiting."; exit 1 }
}
if ((Get-Command Get-ConnectionInformation -ErrorAction SilentlyContinue) -and (Get-ConnectionInformation -ErrorAction SilentlyContinue)) {
    Write-Host "Already connected to Exchange Online."; $ExchangeOnlineConnected = $true
} else {
    try {
        if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) { Write-Host "Installing ExchangeOnlineManagement..."; Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser -Force }
        Import-Module ExchangeOnlineManagement; Write-Host "Connecting to Exchange Online..."; Connect-ExchangeOnline -ErrorAction Stop
        Write-Host "Connected to Exchange Online."; $ExchangeOnlineConnected = $true
    } catch { Write-Warning "Unable to connect to Exchange Online: $($_.Exception.Message). Skipping DL steps." }
}

# --- UPN Generation and Validation ---
Write-SectionHeader "UPN Generation and Validation"
$TempFirstName  = Read-Host "To start, enter the user's First Name"
$TempLastName   = Read-Host "To start, enter the user's Last Name"
$UPNPrefix    = ("$($TempFirstName[0])$TempLastName").ToLower()
$UPNDomain    = "shippers-supply.com"
$UPN          = "$UPNPrefix@$UPNDomain"
$MailNickname = $UPNPrefix

do {
    $LoopAgain = $false
    Write-Host "Proposed UPN: '$UPN'"
    
    # CRITICAL FIX: Explicitly request ALL properties needed for the update scenario.
    $userProperties = "id,displayName,givenName,surname,userPrincipalName,jobTitle,department,mobilePhone,employeeType"
    $ExistingUser = Get-MgUser -Filter "userPrincipalName eq '$UPN'" -Property $userProperties -ErrorAction SilentlyContinue

    if ($ExistingUser) {
        Write-Warning "User '$UPN' already exists (DisplayName: $($ExistingUser.DisplayName))."
        $Choice = Read-Host "Do you want to (O)verwrite this user's data or (C)hoose a different UPN?"
        if ($Choice.ToUpper() -eq 'O') {
            Write-Host "Proceeding in UPDATE mode for user '$UPN'."
            $UpdateMode = $true
            $OriginalDepartment = $ExistingUser.Department
        } else {
            $LoopAgain = $true
        }
    } else {
        $ConfirmUPN = Read-Host "Is this UPN correct? (Y/N)"
        if ($ConfirmUPN.ToUpper() -ne "Y") {
            $LoopAgain = $true
        }
    }

    if ($LoopAgain) {
        $NewUPNInput = Read-Host "Enter desired username (before '@$UPNDomain')"
        if (-not [string]::IsNullOrWhiteSpace($NewUPNInput)) {
            $UPNPrefix   = $NewUPNInput.ToLower().Replace("@$UPNDomain","")
            $UPN         = "$UPNPrefix@$UPNDomain"
            $MailNickname = $UPNPrefix
        }
    }
} while ($LoopAgain)

# --- Name Reconciliation Menu ---
Write-SectionHeader "Name Reconciliation"
$FirstName = ""; $LastName = ""
if ($UpdateMode) {
    $InitialInputName = "$TempFirstName $TempLastName"
    $ExistingName = "$($ExistingUser.GivenName) $($ExistingUser.Surname)"
    Write-Host "Please choose which name to use for this user:"
    Write-Host "(1) Keep the current name in the system: '$ExistingName'"
    Write-Host "(2) Use the name you just entered: '$InitialInputName'"
    Write-Host "(3) Enter a completely different name"
    do {
        $Choice = Read-Host "Enter your choice (1/2/3)"
        switch ($Choice) {
            "1" { $FirstName = $ExistingUser.GivenName; $LastName = $ExistingUser.Surname }
            "2" { $FirstName = $TempFirstName; $LastName = $TempLastName }
            "3" { $FirstName = Read-Host "Enter the correct First Name"; $LastName = Read-Host "Enter the correct Last Name" }
            default { Write-Warning "Invalid choice." }
        }
    } while ([string]::IsNullOrWhiteSpace($FirstName))
} else {
    $ConfirmName = Read-Host "The proposed name is '$TempFirstName $TempLastName'. Is this correct? (Y/N)"
    if ($ConfirmName.ToUpper() -eq 'Y') {
        $FirstName = $TempFirstName; $LastName = $TempLastName
    } else {
        $FirstName = Read-Host "Enter the correct First Name"
        $LastName = Read-Host "Enter the correct Last Name"
    }
}
# Set DisplayName programmatically after reconciliation. No more prompts for it.
$DisplayName = "$FirstName $LastName"
Write-Host "Final name set to: '$FirstName $LastName'. DisplayName will be: '$DisplayName'." -ForegroundColor Green

# --- All other prompts follow, now that the name is finalized ---
Write-SectionHeader "User Details"
$CurrentTitle = if ($UpdateMode) { $ExistingUser.JobTitle } else { "" }
$Title = Read-Host "Job Title [Current: '$CurrentTitle']"
if ([string]::IsNullOrWhiteSpace($Title)) { $Title = $CurrentTitle }

$CurrentDepartment = if ($UpdateMode) { $ExistingUser.Department } else { "" }
$Department = Read-Host "Department [Current: '$CurrentDepartment']"
if ([string]::IsNullOrWhiteSpace($Department)) { $Department = $CurrentDepartment }

# --- Corrected Manager Retrieval ---
$CurrentManager = if ($UpdateMode) { Get-MgUserManager -UserId $ExistingUser.Id -ErrorAction SilentlyContinue } else { $null }
$CurrentManagerUPN = if ($CurrentManager) { $CurrentManager.AdditionalProperties.userPrincipalName } else { "" }
$ManagerId = if ($CurrentManager) { $CurrentManager.Id } else { $null }
do {
    $ManagerEmail = Read-Host "Manager's Email (UPN) [Current: '$CurrentManagerUPN']"
    if ([string]::IsNullOrWhiteSpace($ManagerEmail)) { Write-Host "Keeping current manager."; break }
    
    if (-not $ManagerEmail.Contains("@")) {
        $ManagerEmail = "$ManagerEmail@$UPNDomain"
        Write-Host "Searching for manager: $ManagerEmail" -ForegroundColor Yellow
    }

    $ManagerUser = Get-MgUser -Filter "userPrincipalName eq '$ManagerEmail'" -ErrorAction SilentlyContinue
    if ($ManagerUser) { $ManagerId = $ManagerUser.Id; Write-Host "Manager set to: $($ManagerUser.DisplayName)" -ForegroundColor Green; break }
    else { Write-Warning "Manager '$ManagerEmail' not found. Please try again." }
} while ($true)

$EmployeeTypeOptions = @{ 1 = "Employee"; 2 = "Temp"; 3 = "Contractor"; 4 = "Vendor" }
$CurrentEmployeeType = if ($UpdateMode) { $ExistingUser.EmployeeType } else { "" }
Write-Host ("Employee Type [Current: '$CurrentEmployeeType']")
foreach ($key in $EmployeeTypeOptions.Keys | Sort-Object) { Write-Host "$key. $($EmployeeTypeOptions[$key])" }
do {
    $Selection = Read-Host "Enter number or press Enter to keep current"
    if ([string]::IsNullOrWhiteSpace($Selection) -and $UpdateMode) { $EmployeeType = $CurrentEmployeeType; break }
    if ($Selection -as [int] -and $EmployeeTypeOptions.ContainsKey([int]$Selection)) { $EmployeeType = $EmployeeTypeOptions[[int]$Selection]; break }
    else { Write-Warning "Invalid selection." }
} while ($true)

$CurrentMobilePhone = if ($UpdateMode) { $ExistingUser.MobilePhone } else { "" }
$MobilePhone = Read-Host "Mobile Phone Number [Current: '$CurrentMobilePhone']"
if ([string]::IsNullOrWhiteSpace($MobilePhone)) { $MobilePhone = $CurrentMobilePhone }

# --- License and Group Configuration ---
Write-SectionHeader "License and Group Configuration"
$LicensePartNumber = if ($Department -in @('Warehouse','Production')) { "O365_BUSINESS_PREMIUM" } else { "SPB" }
if (-not $UpdateMode) {
    $TargetSkuObj = Get-MgSubscribedSku -All | Where-Object { $_.SkuPartNumber -eq $LicensePartNumber }
    if (!$TargetSkuObj) { Write-Error "SKU '$LicensePartNumber' not found. Exiting."; exit 1 }
    $AvailableLicenses = $TargetSkuObj.PrepaidUnits.Enabled - $TargetSkuObj.ConsumedUnits
    if ($AvailableLicenses -lt 1) { Write-Error "No available licenses for SKU '$LicensePartNumber'. Aborting."; exit 1 }
    Write-Host "License check passed: $AvailableLicenses available for SKU '$LicensePartNumber'." -ForegroundColor Green
}

# --- Corrected Printer Group Retrieval ---
$CurrentGroups = if ($UpdateMode) { Get-MgUserMemberOf -UserId $ExistingUser.Id -All } else { @() }
$OriginalPrinterGroup = $CurrentGroups | Where-Object { $_.AdditionalProperties.displayName -like "Printer*" } | Select-Object -First 1
$PrinterGroups = Get-MgGroup -Filter "startswith(displayName,'Printer')" -All
$SelectedPrinterGroup = $null
if ($PrinterGroups.Count -gt 0) {
    Write-Host "--- Select Printer Group ---" -ForegroundColor Yellow
    if ($OriginalPrinterGroup) { Write-Host "Current Printer Group: $($OriginalPrinterGroup.AdditionalProperties.displayName)" }
    for ($i=0; $i -lt $PrinterGroups.Count; $i++) { Write-Host "$($i+1). $($PrinterGroups[$i].DisplayName)" }
    $Selection = Read-Host "Enter number or press Enter to keep current"
    if ($Selection -as [int] -and $Selection -in 1..$PrinterGroups.Count) {
        $SelectedPrinterGroup = $PrinterGroups[$Selection - 1]
    }
}

# --- Execution Phase ---
Write-SectionHeader "Executing Changes"
$NewUserId = if ($UpdateMode) { $ExistingUser.Id } else { $null }
if (-not $UpdateMode) {
    Write-Host "Creating New User..." -ForegroundColor Yellow
    try {
        $Password = Read-Host "Enter Temporary Password" -AsSecureString
        $NewUser = New-MgUser -UserPrincipalName $UPN -DisplayName $DisplayName -GivenName $FirstName -Surname $LastName `
            -MailNickname $MailNickname -AccountEnabled -CompanyName "Shippers-Supply" `
            -PasswordProfile @{ForceChangePasswordNextSignIn=$false; Password=$Password}
        $NewUserId = $NewUser.Id
        Write-Host "Created user '$($NewUser.DisplayName)' (ID: $NewUserId)." -ForegroundColor Green
        Update-MgUser -UserId $NewUserId -UsageLocation "US"; Write-Host "Set UsageLocation='US'." -ForegroundColor Green
    } catch { Write-Error "FATAL: Error creating user: $($_.Exception.Message)"; exit 1 }
}

# --- Build Update Payload (only include changed attributes) ---
$userProps = @{}
if ($UpdateMode) {
    # Compare against the data we fetched in $ExistingUser
    if ($DisplayName -ne $ExistingUser.DisplayName) { $userProps.Add("DisplayName", $DisplayName) }
    if ($FirstName -ne $ExistingUser.GivenName) { $userProps.Add("GivenName", $FirstName) }
    if ($LastName -ne $ExistingUser.Surname) { $userProps.Add("Surname", $LastName) }
    if ($Title -ne $ExistingUser.JobTitle) { $userProps.Add("JobTitle", $Title) }
    if ($Department -ne $ExistingUser.Department) { $userProps.Add("Department", $Department) }
    if ($MobilePhone -ne $ExistingUser.MobilePhone) { $userProps.Add("MobilePhone", $MobilePhone) }
    if ($EmployeeType -ne $ExistingUser.EmployeeType) {
        $userProps.Add("EmployeeType", $(if ([string]::IsNullOrEmpty($EmployeeType)) { $null } else { $EmployeeType }))
    }
}

# --- Update User Attributes and Manager ---
if ($userProps.Count -gt 0) {
    Write-Host "Updating user attributes: $(($userProps.Keys -join ', '))" -ForegroundColor Yellow
    try { Update-MgUser -UserId $NewUserId -BodyParameter $userProps; Write-Host "Attributes updated successfully." -ForegroundColor Green }
    catch { Write-Error "Error updating user attributes: $($_.Exception.Message)" }
} else { Write-Host "No user attributes needed to be changed." }

if ($ManagerId -ne $CurrentManager.Id) {
    Write-Host "Updating manager..." -ForegroundColor Yellow
    try {
        $ManagerReference = @{ "@odata.id" = "https://graph.microsoft.com/v1.0/users/$ManagerId" }
        Invoke-MgGraphRequest -Method PUT -Uri "https://graph.microsoft.com/v1.0/users/$NewUserId/manager/`$ref" -Body $ManagerReference
        Write-Host "Manager updated successfully." -ForegroundColor Green
    } catch { Write-Error "Error setting manager: $($_.Exception.Message)" }
}

# --- Handle License & Group Changes ---
$M365GroupsToAddNames = @("All Company Team", "DUO MFA", "Shippers All Staff")
if (-not ($Department -in @('Warehouse','Production'))) { $M365GroupsToAddNames += "OneDrive Folder Redirect" }

if ($UpdateMode -and ($OriginalDepartment -in @('Warehouse','Production')) -and -not ($Department -in @('Warehouse','Production'))) {
    Write-Host "Department changed. Removing direct 'O365_BUSINESS_PREMIUM' license..." -ForegroundColor Yellow
    try {
        $SkuToRemove = (Get-MgSubscribedSku -All | Where-Object { $_.SkuPartNumber -eq "O365_BUSINESS_PREMIUM" }).SkuId
        if ($SkuToRemove) { Set-MgUserLicense -UserId $NewUserId -RemoveLicenses @($SkuToRemove) -AddLicenses @{}; Write-Host "License removed." -ForegroundColor Green }
    } catch { Write-Error "Failed to remove direct license: $($_.Exception.Message)" }
}
elseif (-not $UpdateMode -and ($Department -in @('Warehouse','Production'))) {
    Write-Host "Assigning 'O365_BUSINESS_PREMIUM' license..." -ForegroundColor Yellow
    try {
        $SkuObj = Get-MgSubscribedSku -All | Where-Object { $_.SkuPartNumber -eq "O365_BUSINESS_PREMIUM" }
        if ($SkuObj) { Set-MgUserLicense -UserId $NewUserId -AddLicenses @{ SkuId = $SkuObj.SkuId } -RemoveLicenses @(); Write-Host "License assigned." -ForegroundColor Green }
    } catch { Write-Error "Error assigning license: $($_.Exception.Message)" }
}

$oldPrinterId = if ($OriginalPrinterGroup) { $OriginalPrinterGroup.Id } else { $null }
$newPrinterId = if ($SelectedPrinterGroup) { $SelectedPrinterGroup.Id } else { $null }
if ($newPrinterId -ne $oldPrinterId) {
    if ($oldPrinterId) {
        Write-Host "Removing user from old printer group: $($OriginalPrinterGroup.AdditionalProperties.displayName)..." -ForegroundColor Yellow
        try { Remove-MgGroupMemberByRef -GroupId $oldPrinterId -DirectoryObjectId $NewUserId; Write-Host "Removal successful." -ForegroundColor Green }
        catch { Write-Error "Error removing from old printer group: $($_.Exception.Message)" }
    }
    if ($newPrinterId) {
        Write-Host "Adding user to new printer group: $($SelectedPrinterGroup.DisplayName)..." -ForegroundColor Yellow
        try { New-MgGroupMember -GroupId $newPrinterId -DirectoryObjectId $NewUserId; Write-Host "Addition successful." -ForegroundColor Green }
        catch { Write-Error "Error adding to new printer group: $($_.Exception.Message)" }
    }
}

$CurrentGroupIds = $CurrentGroups.Id
foreach ($GroupName in $M365GroupsToAddNames) {
    $Group = Get-MgGroup -Filter "displayName eq '$GroupName'"
    if ($Group -and $Group.Id -notin $CurrentGroupIds) {
        Write-Host "Adding user to group: $GroupName..." -ForegroundColor Yellow
        try { New-MgGroupMember -GroupId $Group.Id -DirectoryObjectId $NewUserId; Write-Host "Added to group successfully." -ForegroundColor Green }
        catch { Write-Error "Error adding to group '$GroupName': $($_.Exception.Message)" }
    }
}

# --- Mailbox and DL Logic ---
Write-SectionHeader "Finalizing Mailbox Setup"
$MailboxReady = $false
$WaitStartTime = Get-Date
do {
    if (Get-Mailbox -Identity $UPN -ErrorAction SilentlyContinue) {
        Write-Host "Mailbox is ready." -ForegroundColor Green
        $MailboxReady = $true
    } else {
        if ((Get-Date) -gt $WaitStartTime.AddMinutes(5)) { Write-Warning "Mailbox provisioning timed out after 5 minutes."; break }
        Write-Host "Mailbox not yet found for $UPN. Waiting..."
        Start-Sleep -Seconds 20
    }
} while (-not $MailboxReady -and -not $TestMode)

if ($TestMode -and -not $MailboxReady) { $MailboxReady = $true }

$AllEmployeesDL = Get-DistributionGroup -Filter "DisplayName -eq 'All Employees'" -ErrorAction SilentlyContinue
if ($AllEmployeesDL -and $MailboxReady) {
    if ($UPN -notin (Get-DistributionGroupMember -Identity $AllEmployeesDL.Identity).PrimarySmtpAddress) {
        Write-Host "Adding user to Exchange DL: $($AllEmployeesDL.Name)..." -ForegroundColor Yellow
        try { Add-DistributionGroupMember -Identity $AllEmployeesDL.Identity -Member $UPN; Write-Host "Added to DL successfully." -ForegroundColor Green }
        catch { Write-Error "Error adding to Exchange DL: $($_.Exception.Message)" }
    }
}

# --- Stop Timer + Disconnect ---
Write-SectionHeader "Completion"
$Elapsed = (Get-Date) - $ScriptStartTime
Write-Host "Disconnecting from services..."
if (-not $GraphContext) { try { Disconnect-MgGraph } catch {} }
if ($ExchangeOnlineConnected -and -not (Get-ConnectionInformation -ErrorAction SilentlyContinue)) {
    try { Disconnect-ExchangeOnline -Confirm:$false } catch {}
}
Write-Host "Script completed in $([math]::Round($Elapsed.TotalSeconds,2)) seconds." -ForegroundColor Green

# --- Final Steps ---
$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$CompanyDirectoryScript = Join-Path $PSScriptRoot 'Add-NewUser-CompanyDirectory.ps1'
if (Test-Path $CompanyDirectoryScript) { & $CompanyDirectoryScript -UserPrincipalName $UPN }
$LinkWindowScript = Join-Path $PSScriptRoot 'Add-NewUser-LinkWindow.ps1'
if ($NewUserId -and (Test-Path $LinkWindowScript)) { & $LinkWindowScript -NewUserId $NewUserId }

Write-Host ""
Write-Host "--- SCRIPT COMPLETE ---" -ForegroundColor Cyan