<#
.SYNOPSIS
    Adds (or tests adding) a user to the People web part on Company-Directory.aspx using Microsoft Graph.

.DESCRIPTION
    - Self-contained script that installs and imports only required Graph modules
    - Uses Microsoft Graph PowerShell to get real AAD Object ID and job title
    - Connects to SharePoint Online using PnP.PowerShell
    - Adds the specified user into the "persons" array with real AAD Object ID
    - Sorts the "persons" array alphabetically by email address (id field)
    - If run with –Test, outputs the exact JSON that would be injected without writing

.PARAMETER UserPrincipalName
    The UPN (email) of the user to add. Defaults to value in script configuration.

.PARAMETER Test
    If specified, do not write back changes; only show the exact JSON that would be injected.

.EXAMPLE
    .\Update-CompanyDirectory-Clean.ps1 -UserPrincipalName "jdoe@shippers-supply.com"

.EXAMPLE
    .\Update-CompanyDirectory-Clean.ps1 -Test

.NOTES
    - Automatically installs Microsoft.Graph.Authentication and Microsoft.Graph.Users if needed
    - Handles Graph authentication automatically
    - Uses real AAD Object IDs from Microsoft Graph
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$UserPrincipalName = "testuser@shippers-supply.com",

    [Parameter(Mandatory = $false)]
    [switch]$Test
)

#region Configuration - Modify these values for your environment
$SHAREPOINT_SITE_URL = "https://shipperssupply.sharepoint.com"
$SHAREPOINT_PAGE_NAME = "Company-Directory.aspx"
$PEOPLE_WEBPART_ID = "7f718435-ee4d-431c-bdbf-9c4ff326f46e"
$DEFAULT_USER_UPN = "testuser@shippers-supply.com"

# Use default UPN if none provided
if ([string]::IsNullOrWhiteSpace($UserPrincipalName)) {
    $UserPrincipalName = $DEFAULT_USER_UPN
}
#endregion

function Ensure-Module {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $false)]
        [string]$MinimumVersion
    )
    
    $installedModule = Get-Module -ListAvailable -Name $Name | Sort-Object Version -Descending | Select-Object -First 1
    
    if (-not $installedModule) {
        Install-Module -Name $Name -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop | Out-Null
    } elseif ($MinimumVersion -and $installedModule.Version -lt [Version]$MinimumVersion) {
        Update-Module -Name $Name -Force -ErrorAction Stop | Out-Null
    }
    
    Import-Module $Name -Force -ErrorAction Stop | Out-Null
}

function Test-GraphConnection {
    try {
        $context = Get-MgContext
        if ($context -and $context.Scopes -contains 'User.Read.All') {
            return $true
        }
        return $false
    }
    catch {
        return $false
    }
}

function Connect-ToGraph {
    try {
        Connect-MgGraph -Scopes 'User.Read.All' -NoWelcome -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        Write-Error "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
        return $false
    }
}

try {
    # 1. Ensure required modules are installed and imported
    Ensure-Module -Name "PnP.PowerShell"
    Ensure-Module -Name "Microsoft.Graph.Authentication"
    Ensure-Module -Name "Microsoft.Graph.Users"

    # 2. Check/establish Microsoft Graph connection
    if (-not (Test-GraphConnection)) {
        if (-not (Connect-ToGraph)) {
            throw "Failed to establish Microsoft Graph connection"
        }
    }

    # 3. Get user information from Microsoft Graph
    try {
        $mgUser = Get-MgUser -UserId $UserPrincipalName -ErrorAction Stop
        $aadObjectId = $mgUser.Id
        $jobTitle = $mgUser.JobTitle  # Use exactly what's in AD - could be null/empty
        $displayName = if ($mgUser.DisplayName) { $mgUser.DisplayName } else { $UserPrincipalName.Split('@')[0] }
        
        # Validate required fields
        if ([string]::IsNullOrWhiteSpace($aadObjectId)) {
            throw "AAD Object ID is required but was empty"
        }
    }
    catch {
        Write-Error "Failed to retrieve user from Microsoft Graph: $($_.Exception.Message)"
        throw
    }

    # 4. Connect to SharePoint Online
    try {
        Connect-PnPOnline $SHAREPOINT_SITE_URL -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Error "Failed to connect to SharePoint Online: $($_.Exception.Message)"
        throw
    }

    # 5. Load the SharePoint page and web part
    $page = Get-PnPClientSidePage -Identity $SHAREPOINT_PAGE_NAME -ErrorAction Stop
    $ctrl = $page.Controls | Where-Object { $_.WebPartId -eq $PEOPLE_WEBPART_ID }
    if (-not $ctrl) {
        throw "Could not locate the People web part (ID $PEOPLE_WEBPART_ID) on $SHAREPOINT_PAGE_NAME."
    }

    # 6. Process the web part JSON
    $rawJson = $ctrl.Properties.GetRawText()
    $props = $rawJson | ConvertFrom-Json

    # Build new person object (matching existing JSON structure: id, role, aadObjectId)
    $newPerson = [PSCustomObject]@{
        id          = $UserPrincipalName
        role        = if ([string]::IsNullOrWhiteSpace($jobTitle)) { "" } else { $jobTitle }
        aadObjectId = $aadObjectId
    }

    # Ensure the "persons" array exists
    if (-not $props.persons) {
        $props.persons = @()
    }

    # Check if the user already exists
    $existing = $props.persons | Where-Object { $_.id -eq $UserPrincipalName }
    if ($existing) {
        $existing.role = if ([string]::IsNullOrWhiteSpace($jobTitle)) { "" } else { $jobTitle }
        $existing.aadObjectId = $aadObjectId
        $action = "Updated"
    }
    else {
        $props.persons += $newPerson
        $action = "Added"
    }

    # Validate no duplicate AAD Object IDs (can cause image confusion in SharePoint)
    $duplicateAADIds = $props.persons | Group-Object aadObjectId | Where-Object { $_.Count -gt 1 -and $_.Name -ne "" }
    if ($duplicateAADIds) {
        Write-Warning "Found duplicate AAD Object IDs in directory:"
        $duplicateAADIds | ForEach-Object {
            Write-Warning "  AAD ID $($_.Name) used by: $($_.Group.id -join ', ')"
        }
    }

    # Sort alphabetically by email address
    $props.persons = $props.persons | Sort-Object id

    # Convert to JSON
    $updatedJson = $props | ConvertTo-Json -Depth 10

    if ($Test) {
        Write-Host "TEST MODE: $action user '$UserPrincipalName' ($displayName)" -ForegroundColor Yellow
        Write-Host "Job Title: $(if([string]::IsNullOrWhiteSpace($jobTitle)) { '[EMPTY]' } else { $jobTitle })" -ForegroundColor Gray
        Write-Host "AAD Object ID: $aadObjectId" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Updated JSON:" -ForegroundColor Cyan
        Write-Host $updatedJson
    }
    else {
        try {
            # Direct property modification (Microsoft documented approach)
            $ctrl.PropertiesJson = $updatedJson
            $page.Save()
            
            # Force republish to clear SharePoint's People web part cache
            Start-Sleep -Seconds 2  # Give SharePoint time to process
            $page.Publish("Updated company directory")
            
            # Additional cache clearing - republish again after brief delay
            Start-Sleep -Seconds 1
            $page.Publish("Refreshed company directory")
            
            Write-Host "$action user '$UserPrincipalName' in company directory" -ForegroundColor Green
        }
        catch {
            # Fallback method
            $newCmdlet = Get-Command "Set-PnPPageWebPart" -ErrorAction SilentlyContinue
            if ($newCmdlet -and $ctrl.InstanceId) {
                try {
                    Set-PnPPageWebPart -Page $SHAREPOINT_PAGE_NAME -Identity $ctrl.InstanceId -PropertiesJson $updatedJson -ErrorAction Stop
                    
                    # Force republish to clear SharePoint's People web part cache
                    Start-Sleep -Seconds 2
                    $page.Publish("Refreshed company directory")
                    
                    Write-Host "$action user '$UserPrincipalName' in company directory" -ForegroundColor Green
                }
                catch {
                    throw "Failed to update web part: $($_.Exception.Message)"
                }
            }
            else {
                throw "Failed to update web part: $($_.Exception.Message)"
            }
        }
    }
}
catch {
    Write-Error "ERROR: $($_.Exception.Message)"
    exit 1
}