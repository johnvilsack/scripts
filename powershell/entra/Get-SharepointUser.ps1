[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$UserPrincipalName = "testuser@shippers-supply.com"
)

function Ensure-Module {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )
    if (-not (Get-Module -ListAvailable -Name $Name)) {
        Write-Host "Installing module '$Name'..."
        Install-Module -Name $Name -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    }
    Import-Module $Name -ErrorAction Stop
}

try {
    # Ensure PnP.PowerShell is installed and imported
    Ensure-Module -Name "PnP.PowerShell"

    # Connect to SharePoint Online
    Write-Host "Connecting to SharePoint Online..."
    Connect-PnPOnline "https://shipperssupply.sharepoint.com" -ErrorAction Stop

    # Method 1: Try to get AAD Object ID using Get-PnPAzureADUser (might fail due to Graph issues)
    Write-Host ""
    Write-Host "=== METHOD 1: PnP Azure AD User (might fail) ===" -ForegroundColor Yellow
    try {
        $aadUser = Get-PnPAzureADUser -Identity $UserPrincipalName -ErrorAction Stop
        Write-Host "SUCCESS: Get-PnPAzureADUser worked!" -ForegroundColor Green
        Write-Host "AAD Object ID: $($aadUser.Id)" -ForegroundColor Cyan
        Write-Host "Display Name: $($aadUser.DisplayName)" -ForegroundColor Cyan
        Write-Host "Job Title: $($aadUser.JobTitle)" -ForegroundColor Cyan
        Write-Host "Full AAD User object:" -ForegroundColor Cyan
        $aadUser | Format-List *
    }
    catch {
        Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
    }

    # Method 2: Get SharePoint user and try to expand UserId
    Write-Host ""
    Write-Host "=== METHOD 2: SharePoint User with UserId expansion ===" -ForegroundColor Yellow
    try {
        $spUser = Get-PnPUser | Where-Object { $_.Email -eq $UserPrincipalName }
        if ($spUser) {
            Write-Host "Found SharePoint user: $($spUser.Title)" -ForegroundColor Green
            
            # Try to load and expand the UserId property
            $context = Get-PnPContext
            $context.Load($spUser.UserId)
            $context.ExecuteQuery()
            
            Write-Host "UserId object properties:" -ForegroundColor Cyan
            $spUser.UserId | Get-Member -MemberType Properties | ForEach-Object {
                $propName = $_.Name
                try {
                    $propValue = $spUser.UserId.$propName
                    Write-Host "  $propName : $propValue" -ForegroundColor Gray
                }
                catch {
                    Write-Host "  $propName : [Error reading property]" -ForegroundColor Red
                }
            }
        }
        else {
            Write-Host "User not found in SharePoint" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
    }

    # Method 3: Try to extract from LoginName
    Write-Host ""
    Write-Host "=== METHOD 3: Extract from LoginName ===" -ForegroundColor Yellow
    try {
        $spUser = Get-PnPUser | Where-Object { $_.Email -eq $UserPrincipalName }
        if ($spUser) {
            Write-Host "LoginName: $($spUser.LoginName)" -ForegroundColor Cyan
            
            # Parse the claims identity format
            if ($spUser.LoginName -match "i:0#\.f\|membership\|(.+)") {
                $extractedUPN = $matches[1]
                Write-Host "Extracted UPN from LoginName: $extractedUPN" -ForegroundColor Green
            }
            
            # Check if there's any GUID-like pattern in the LoginName
            if ($spUser.LoginName -match "([a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12})") {
                $extractedGuid = $matches[1]
                Write-Host "Found GUID-like pattern: $extractedGuid" -ForegroundColor Green
            }
            else {
                Write-Host "No GUID pattern found in LoginName" -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
    }

    # Method 4: Try REST API call to get user info
    Write-Host ""
    Write-Host "=== METHOD 4: REST API call ===" -ForegroundColor Yellow
    try {
        $restUser = Invoke-PnPSPRestMethod -Url "/_api/web/siteusers?`$filter=Email eq '$UserPrincipalName'&`$select=*" -Method Get
        if ($restUser.value -and $restUser.value.Count -gt 0) {
            $user = $restUser.value[0]
            Write-Host "REST API user data:" -ForegroundColor Green
            $user.PSObject.Properties | ForEach-Object {
                Write-Host "  $($_.Name): $($_.Value)" -ForegroundColor Gray
            }
        }
        else {
            Write-Host "No user found via REST API" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
    }

    # Method 5: Check what we actually have in existing directory entries
    Write-Host ""
    Write-Host "=== METHOD 5: Check existing directory entries ===" -ForegroundColor Yellow
    try {
        $page = Get-PnPClientSidePage -Identity "Company-Directory.aspx" -ErrorAction Stop
        $peopleWebPartId = "7f718435-ee4d-431c-bdbf-9c4ff326f46e"
        $ctrl = $page.Controls | Where-Object { $_.WebPartId -eq $peopleWebPartId }
        if ($ctrl) {
            $rawJson = $ctrl.Properties.GetRawText()
            $props = $rawJson | ConvertFrom-Json
            if ($props.persons -and $props.persons.Count -gt 0) {
                Write-Host "Existing directory entries and their aadObjectId values:" -ForegroundColor Green
                $props.persons | ForEach-Object {
                    Write-Host "  $($_.id) -> aadObjectId: $($_.aadObjectId)" -ForegroundColor Gray
                }
                
                Write-Host ""
                Write-Host "Sample aadObjectId formats found:" -ForegroundColor Cyan
                $props.persons | ForEach-Object { $_.aadObjectId } | Select-Object -Unique | ForEach-Object {
                    Write-Host "  $_" -ForegroundColor Gray
                }
            }
            else {
                Write-Host "No existing persons in directory" -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
    }

}
catch {
    Write-Error "ERROR: $($_.Exception.Message)"
    exit 1
}