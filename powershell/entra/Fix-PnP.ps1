# --------------------------------------------------------
# PowerShell (macOS) – Remove Microsoft.Graph.Core.dll from PnP.PowerShell
# --------------------------------------------------------

# 1. Force-unload PnP.PowerShell if currently loaded
if (Get-Module -Name PnP.PowerShell) {
    Write-Host "Unloading PnP.PowerShell module from current session..."
    Remove-Module -Name PnP.PowerShell -Force
}

# 2. Locate the PnP.PowerShell module directory (user scope)
$PnPModuleInfo = Get-Module -ListAvailable PnP.PowerShell | Sort-Object Version -Descending | Select-Object -First 1
if (-not $PnPModuleInfo) {
    Write-Error "PnP.PowerShell module not found in any PSModulePath."
    exit 1
}

$PnPModulePath = $PnPModuleInfo.ModuleBase
Write-Host "Found PnP.PowerShell at: $PnPModulePath" 

# 3. Construct the path to the outdated Microsoft.Graph.Core.dll
$GraphCoreDllPath = Join-Path -Path $PnPModulePath -ChildPath "Core/Microsoft.Graph.Core.dll"

# 4. Check for existence and delete if present
if (Test-Path -LiteralPath $GraphCoreDllPath) {
    Write-Host "Deleting outdated Graph.Core DLL: $GraphCoreDllPath"
    Remove-Item -LiteralPath $GraphCoreDllPath -Force
    Write-Host "✅ Successfully removed Microsoft.Graph.Core.dll from PnP.PowerShell."
} else {
    Write-Host "No Microsoft.Graph.Core.dll found in the PnP.PowerShell/Core folder. Nothing to remove." 
}
