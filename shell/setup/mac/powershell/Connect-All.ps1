# ~/.config/powershell/Connect-All.ps1

# SharePoint URL from original script
$SharePointUrl = "https://shipperssupply-admin.sharepoint.com"

# Trust PSGallery if not already trusted
if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne 'Trusted') {
    Write-Host "Trusting PSGallery repository..." -ForegroundColor Yellow
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop
}

# All required modules
$modules = @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.Users',
    'Microsoft.Graph.Groups', 
    'Microsoft.Graph.Mail',
    'Microsoft.Graph.Sites',
    'Microsoft.Graph.Files',
    'Microsoft.Graph.Teams',
    'PnP.PowerShell',
    'ExchangeOnlineManagement'
)

# Function to install/import modules cleanly
function Install-AndImport {
    param([string]$ModuleName)
    
    if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
        Write-Host "Installing $ModuleName..." -ForegroundColor Yellow
        Install-Module -Name $ModuleName -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    }
    
    Write-Host "Importing $ModuleName..." -ForegroundColor DarkCyan
    Import-Module $ModuleName -ErrorAction Stop
}

# Install and import all modules
foreach ($module in $modules) {
    Install-AndImport -ModuleName $module
}

# Connect to services
Write-Host "`nConnecting to services..." -ForegroundColor Cyan

# Microsoft Graph - simplified scopes
$graphScopes = @(
    "User.Read.All",
    "Group.ReadWrite.All", 
    "Mail.ReadWrite",
    "Sites.ReadWrite.All",
    "Files.ReadWrite.All",
    "Team.ReadBasic.All"  # Simplified Teams scope
)

Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
try {
    Connect-MgGraph -Scopes $graphScopes -NoWelcome
    Write-Host "✓ Connected to Microsoft Graph" -ForegroundColor Green
}
catch {
    Write-Warning "Failed to connect to Microsoft Graph: $_"
}

# Exchange Online
Write-Host "Connecting to Exchange Online..." -ForegroundColor Cyan
try {
    Connect-ExchangeOnline -ShowBanner:$false
    Write-Host "✓ Connected to Exchange Online" -ForegroundColor Green
}
catch {
    Write-Warning "Failed to connect to Exchange Online: $_"
}

Write-Host "`nConnection script completed!" -ForegroundColor Green