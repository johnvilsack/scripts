function Prompt {
  # Write a green “>” and then a space; return a space so PowerShell doesn’t append “PS>” again
  Write-Host '> ' -NoNewline -ForegroundColor Green
  return ' '
}



# Register a handler that fires when PowerShell is exiting
# Suppress the subscriber object:
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Write-Host "Disconnecting modules..." -ForegroundColor Yellow
    # Suppress any errors so exit never gets blocked
    try {
        if (Get-Module Microsoft.Graph -ListAvailable -ErrorAction SilentlyContinue) {
            # If you used Connect-MgGraph, this will tear down the session
            Disconnect-MgGraph -Confirm:$false
        }
    } catch {}

    try {
        if (Get-Module ExchangeOnlineManagement -ListAvailable -ErrorAction SilentlyContinue) {
            # -Confirm:$false avoids the “Are you sure?” prompt
            Disconnect-ExchangeOnline -Confirm:$false
        }
    } catch {}

    try {
        if (Get-Module MicrosoftTeams -ListAvailable -ErrorAction SilentlyContinue) {
            Disconnect-MicrosoftTeams
        }
    } catch {}

    try {
        if (Get-Module PnP.PowerShell -ListAvailable -ErrorAction SilentlyContinue) {
            # This disconnects all PnPOnline connections
            Disconnect-PnPOnline -All -ErrorAction SilentlyContinue
        }
    } catch {}
}
