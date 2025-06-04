<#
.SYNOPSIS
  Export all message-trace detail events for a mailbox in the past 24 hrs to a CSV.
.PARAMETER user
  The User Principal Name (email) to trace.
.EXAMPLE
  .\Get-AllTraceEventsCsv.ps1 -user alice@contoso.com
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$user
)

# Load module and connect
Import-Module ExchangeOnlineManagement
Connect-ExchangeOnline -ShowBanner:$false

# Define time window
$start = (Get-Date).AddHours(-24)
$end   = Get-Date

# 1) Grab high‐level traces
$traces = Get-MessageTrace `
    -RecipientAddress $user `
    -StartDate $start -EndDate $end `
    -PageSize 5000

# 2) Pull all detail events
$allEvents = foreach ($t in $traces) {
    Get-MessageTraceDetail `
      -MessageTraceId $t.MessageTraceId `
      -RecipientAddress $user `
      -ErrorAction SilentlyContinue
}

# 3) Shape output with extra context
$results = $allEvents | ForEach-Object {
    [PSCustomObject]@{
        User            = $user
        MessageTraceId  = $_.MessageTraceId
        ReceivedDate    = $_.ReceivedDate
        EventDate       = $_.EventDate
        Event           = $_.Event
        Source          = $_.Source
        ConnectorId     = $_.ConnectorId
        Detail          = $_.Detail
    }
}

# 4) Build CSV path on Desktop (cross‐platform)
$fileName = "{0}_MessageTraceDetails_{1:yyyyMMdd_HHmm}.csv" -f ($user -replace '@','_'), (Get-Date)
$csvPath  = Join-Path $HOME "Desktop" $fileName

# 5) Export to CSV
$results | Export-Csv -Path $csvPath -NoTypeInformation

Write-Host "Exported $($results.Count) events to $csvPath"

# 6) Disconnect
Disconnect-ExchangeOnline -Confirm:$false
