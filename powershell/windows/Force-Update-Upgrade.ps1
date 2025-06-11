# Force-WindowsUpdate.ps1
# Bypass execution policy for this session
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# Locate the Update client
$uso = "$env:windir\system32\UsoClient.exe"
if (-not (Test-Path $uso)) {
    Write-Error "UsoClient.exe not found; aborting."
    exit 1
}

# 1. Scan for updates
Write-Output "→ Scanning for updates..."
& $uso StartScan | Out-Null

# 2. Download updates (including feature/OS upgrades if a Feature Update profile is in place)
Write-Output "→ Downloading updates..."
& $uso StartDownload | Out-Null

# 3. Install all downloaded updates
Write-Output "→ Installing updates..."
& $uso StartInstall | Out-Null

# Wait a bit for Windows Update to register a reboot requirement
Start-Sleep -Seconds 30

# 4. If a reboot is pending, force it
try {
    $rebootPending = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
} catch {
    $rebootPending = $false
}

if ($rebootPending) {
    Write-Output "→ Reboot pending; restarting now..."
    Restart-Computer -Force
} else {
    Write-Output "→ No reboot required."
}
