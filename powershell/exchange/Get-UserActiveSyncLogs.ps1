<#
.SYNOPSIS
    Retrieve ActiveSync logs for a specific mailbox over the past 24 hours.

.PARAMETER user
    The User Principal Name (email address) of the mailbox to query.

.EXAMPLE
    .\Get-ActiveSyncLogs.ps1 -user alice@contoso.com
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$user
)

# 1) Connect to Exchange Online (requires ExchangeOnlineManagement module)
Connect-ExchangeOnline -ShowBanner:$false                                                                                      # :contentReference[oaicite:0]{index=0}

# 2) Define cutoff for the last 24 hours
$cutoff = (Get-Date).AddHours(-24)

# 3) Retrieve and filter ActiveSync device statistics
$logs = Get-EXOMobileDeviceStatistics -Mailbox $user -ActiveSync -ErrorAction Stop | Where-Object {
    $_.LastSyncAttemptTime -ge $cutoff
}                                                                                                                              # :contentReference[oaicite:1]{index=1}

# 4) Display results (or note if none found)
if ($logs) {
    $logs |
        Select-Object DeviceId, DeviceType, DeviceModel, DeviceOS, LastSyncAttemptTime, LastSuccessSync, Status, DeviceUserAgent |
        Format-Table -AutoSize

    # 5) Export to CSV on your desktop
    $fileName = "{0}_ActiveSyncLogs_{1:yyyyMMdd_HHmm}.csv" -f ($user -replace '@','_'), (Get-Date)
    $csvPath  = Join-Path $env:USERPROFILE\Desktop $fileName
    $logs |
        Select-Object DeviceId, DeviceType, DeviceModel, DeviceOS, LastSyncAttemptTime, LastSuccessSync, Status, DeviceUserAgent |
        Export-Csv -Path $csvPath -NoTypeInformation

    Write-Host "Exported $($logs.Count) entries to $csvPath"
}
else {
    Write-Host "No ActiveSync logs found for $user in the past 24 hours."
}

# 6) Disconnect session
Disconnect-ExchangeOnline -Confirm:$false
