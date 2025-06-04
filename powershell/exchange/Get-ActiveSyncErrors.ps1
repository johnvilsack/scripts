# Requires the ExchangeOnlineManagement module
Import-Module ExchangeOnlineManagement

# 1) Connect silently
Connect-ExchangeOnline -ShowBanner:$false

# 2) Define the cutoff for “past 24 hours”
$cutoff = (Get-Date).AddHours(-128)

# 3) Get all user mailboxes with ActiveSync devices
$mailboxes = Get-EXOMailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox |
             Where-Object HasActiveSyncDevicePartnership -eq $true

# 4) Collect any sync errors
$syncErrors = foreach ($mbx in $mailboxes) {
    # retrieve all ActiveSync devices for this mailbox
    $devs = Get-EXOMobileDeviceStatistics -Mailbox $mbx.UserPrincipalName -ActiveSync -ErrorAction SilentlyContinue
    foreach ($d in $devs) {
        # find devices that attempted to sync in the last 24h but whose last successful sync is older than that attempt
        if ($d.LastSyncAttemptTime -gt $cutoff -and $d.LastSuccessSync -lt $d.LastSyncAttemptTime) {
            [PSCustomObject]@{
                User            = $mbx.UserPrincipalName
                DeviceType      = $d.DeviceType
                DeviceModel     = $d.DeviceModel
                DeviceOS        = $d.DeviceOS
                LastAttempt     = $d.LastSyncAttemptTime
                LastSuccess     = $d.LastSuccessSync
                Status          = $d.Status
                UserAgent       = $d.DeviceUserAgent
            }
        }
    }
}

# 5) Show results
if ($syncErrors) {
    $syncErrors | Sort-Object LastAttempt |
        Format-Table User, DeviceType, DeviceModel, LastAttempt, LastSuccess, Status -AutoSize
} else {
    Write-Host "No ActiveSync sync errors detected in the past 24 hours."
}

# 6) Clean up
Disconnect-ExchangeOnline -Confirm:$false
