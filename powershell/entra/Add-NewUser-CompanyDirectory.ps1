<#
.SYNOPSIS
    Adds (or tests adding) a user to the People web part on Company-Directory.aspx and re-sorts.

.DESCRIPTION
    - Checks for and imports the PnP.PowerShell module if not already loaded.
    - Connects to SharePoint Online using Connect-PnPOnline (relying on a stored Client ID in Keychain).
    - Retrieves the user’s AAD Object ID and job title (role) via Get-PnPAzureADUser.
    - Loads the “Company-Directory.aspx” modern page and locates the People web part by its SPFx WebPartId.
    - Adds the specified user into the “persons” array (using their UPN, AAD Object ID, and job title) if not already present.
    - Sorts the “persons” array by UPN.
    - If run with –Test, outputs the updated JSON without writing; otherwise, writes changes with Set-PnPClientSideWebPart.

.PARAMETER UserPrincipalName
    The UPN (email) of the user to add. Defaults to “testuser@shippers-supply.com”.

.PARAMETER Test
    If specified, do not write back changes; only show what would change.

.EXAMPLE
    .\Update-CompanyDirectory.ps1 -UserPrincipalName "jdoe@shippers-supply.com"
    # Connects, adds/updates “jdoe@shippers-supply.com” with their job title from AAD, sorts, and writes back.

.EXAMPLE
    .\Update-CompanyDirectory.ps1 -Test
    # Uses “testuser@shippers-supply.com”, outputs the updated JSON, but does not write any changes.

.NOTES
    - Requires PnP.PowerShell ≥ v1.11.0 for Get-PnPAzureADUser and client-side page cmdlets.
    - Uses a pre-registered AAD App’s Client ID stored in Keychain via Set-PnPManagedAppId.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$UserPrincipalName = "testuser@shippers-supply.com",

    [Parameter(Mandatory = $false)]
    [switch]$Test
)

function Ensure-Module {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )
    if (-not (Get-Module -ListAvailable -Name $Name)) {
        Write-Host "Installing module '$Name'..."
        Install-Module -Name $Name -Scope CurrentUser -Force -ErrorAction Stop
    }
    Import-Module $Name -ErrorAction Stop
}

try {
    # 1. Ensure PnP.PowerShell is installed and imported
    Ensure-Module -Name "PnP.PowerShell"

    # 2. Connect to SharePoint Online (relies on stored Client ID in Keychain)
    Write-Host "Connecting to SharePoint Online..."
    Connect-PnPOnline "https://shipperssupply.sharepoint.com" -ErrorAction Stop

    # 3. Retrieve AAD Object ID and Job Title (role) via Get-PnPAzureADUser
    Write-Host "Retrieving Azure AD Object ID and Job Title for $UserPrincipalName..."
    $aadUser = Get-PnPAzureADUser -Identity $UserPrincipalName -ErrorAction Stop
    $aadObjectId = $aadUser.Id
    $jobTitle     = if ($aadUser.JobTitle) { $aadUser.JobTitle } else { "No Title" }
    Write-Host "Found AAD Object ID: $aadObjectId; Job Title: '$jobTitle'"

    # 4. Load the modern client-side page
    $pageName = "Company-Directory.aspx"
    Write-Host "Loading page '$pageName'..."
    $page = Get-PnPClientSidePage -Identity $pageName -ErrorAction Stop

    # 5. Locate the People web part by its SPFx WebPartId
    $peopleWebPartId = "7f718435-ee4d-431c-bdbf-9c4ff326f46e"
    $ctrl = $page.Controls | Where-Object { $_.WebPartId -eq $peopleWebPartId }
    if (-not $ctrl) {
        throw "Could not locate the People web part (ID $peopleWebPartId) on $pageName."
    }

    # 6. Convert the control's JSON Properties into a PS object
    $rawJson = $ctrl.Properties.GetRawText()
    $props   = $rawJson | ConvertFrom-Json

    # 7. Build a new person object
    $newPerson = [PSCustomObject]@{
        id          = $UserPrincipalName
        role        = $jobTitle
        aadObjectId = $aadObjectId
    }

    # 8. Ensure the "persons" array exists
    if (-not $props.persons) {
        Write-Host "'persons' array not found in web part JSON. Initializing new array..."
        $props.persons = @()
    }

    # 9. Check if the user already exists in the array
    $existing = $props.persons | Where-Object { $_.id -eq $UserPrincipalName }
    if ($existing) {
        Write-Host "User '$UserPrincipalName' already exists in the directory. Updating job title if changed..."
        if ($existing.role        -ne $jobTitle)     { $existing.role        = $jobTitle }
        if ($existing.aadObjectId -ne $aadObjectId) { $existing.aadObjectId = $aadObjectId }
    }
    else {
        Write-Host "Adding new user '$UserPrincipalName' with job title '$jobTitle'..."
        $props.persons += $newPerson
    }

    # 10. Sort the persons array by UPN (id)
    $props.persons = $props.persons | Sort-Object id

    # 11. Convert back to JSON with sufficient depth
    $updatedJson = $props | ConvertTo-Json -Depth 10

    if ($Test) {
        # 12a. Test mode: Output the updated JSON; do NOT write changes
        Write-Host "=== TEST MODE: No changes will be written back ==="
        Write-Host "Updated 'persons' JSON for People web part:"
        Write-Host $updatedJson
    }
    else {
        # 12b. Write mode: Push updated JSON back into the same web part
        Write-Host "Writing updated properties back to the People web part..."
        Set-PnPClientSideWebPart `
            -Page              $pageName `
            -InstanceId        $ctrl.Id `
            -WebPartProperties $updatedJson `
            -ErrorAction Stop

        Write-Host "Successfully updated '$UserPrincipalName' in Company-Directory.aspx."
    }
}
catch {
    Write-Error "ERROR: $($_.Exception.Message)"
    exit 1
}
