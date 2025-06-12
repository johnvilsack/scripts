<#
.SYNOPSIS
  Retrieves users via Acumatica OData and displays grouped results on screen.

.DESCRIPTION
  - Reads ACU_USERNAME/ACU_PASSWORD from a `.acumatica.env` file located alongside this script.
  - Calls the `_JV-GetUsers` endpoint with Basic Auth and requests JSON.
  - Groups users with no employee record and stale users.
  - Displays the groupings on screen.

.EXAMPLE
  PS> .\Audit-Users.ps1
#>

# -- Locate and parse .acumatica.env --
$envFile = Join-Path $PSScriptRoot '.acumatica.env'
if (-not (Test-Path $envFile)) {
    Throw "Env file not found: $envFile"
}

$creds = @{}
foreach ($line in Get-Content $envFile) {
    $trim = $line.Trim()
    if ($trim -and -not $trim.StartsWith('#') -and $trim.Contains('=')) {
        $parts = $trim -split '=', 2
        $creds[$parts[0].Trim()] = $parts[1].Trim()
    }
}

if (-not ($creds.ContainsKey('ACU_USERNAME') -and $creds.ContainsKey('ACU_PASSWORD'))) {
    Throw "Missing ACU_USERNAME or ACU_PASSWORD in .acumatica.env"
}
$username = $creds['ACU_USERNAME']
$password = $creds['ACU_PASSWORD']

# -- Build request headers --
$pair    = "$username`:$password"
$b64     = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
$headers = @{
    Authorization = "Basic $b64"
    Accept        = 'application/json;odata=nometadata'
}

# -- Call the OData endpoint --
$uri = 'https://shippers-supply.acumatica.com/odata/Shippers%20Supply/_JV-GetUsers?$filter=Active%20eq%20true%20&$select=UserId,EmployeeId,Email,Created,LastActivity,IsEmployeeActive'
try {
    $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
} catch {
    Throw "REST request failed: $_"
}

$data = $response.value
if (-not $data) {
    Write-Warning "No data returned from the endpoint."
    exit 0
}

# -- Group and display results --

# Calculate 6 months ago
$sixMonthsAgo = (Get-Date).AddMonths(-6)

# Filter users with no employee record (null EmployeeId OR null IsEmployeeActive)
# Exclude AcumaticaSupport
$noEmployeeRecord = $data | Where-Object { 
    ([string]::IsNullOrWhiteSpace($_.EmployeeId) -or $_.IsEmployeeActive -eq $null) -and
    $_.UserId -ne 'AcumaticaSupport'
}

# Filter stale users (LastActivity > 6 months ago)
# Exclude DavidKirsch, ThomasHoffman, admin, and AcumaticaSupport
$staleUsers = $data | Where-Object { 
    $_.LastActivity -and 
    [datetime]$_.LastActivity -lt $sixMonthsAgo -and
    $_.UserId -notin @('DavidKirsch', 'ThomasHoffman', 'admin', 'AcumaticaSupport')
}

# Display No Employee Record grouping
Write-Output "================================================================="
Write-Output "USERS WITH NO EMPLOYEE RECORD"
Write-Output "================================================================="
if ($noEmployeeRecord.Count -eq 0) {
    Write-Output "No users without employee records found."
} else {
    Write-Output "Count: $($noEmployeeRecord.Count)"
    Write-Output "----------------------------------------"
    
    # Calculate column widths for No Employee Record section
    $userIdWidth = [Math]::Max(($noEmployeeRecord | ForEach-Object { $_.UserId.Length } | Measure-Object -Maximum).Maximum, "User ID".Length) + 2
    $emailWidth = [Math]::Max(($noEmployeeRecord | ForEach-Object { $_.Email.Length } | Measure-Object -Maximum).Maximum, "Email".Length) + 2
    
    # Display headers
    $headerUserId = "User ID".PadRight($userIdWidth)
    $headerEmail = "Email".PadRight($emailWidth)
    Write-Output "  $headerUserId$headerEmail$("Status")"
    Write-Output "  $("-" * ($userIdWidth-1)) $("-" * ($emailWidth-1)) $("-" * 6)"
    
    $noEmployeeRecord | ForEach-Object {
        $employeeStatus = if ([string]::IsNullOrWhiteSpace($_.EmployeeId)) { "No EmployeeId" } else { "IsEmployeeActive is null" }
        $formattedUserId = $_.UserId.PadRight($userIdWidth)
        $formattedEmail = $_.Email.PadRight($emailWidth)
        Write-Output "  $formattedUserId$formattedEmail$employeeStatus"
    }
}

# Display Stale Users grouping
Write-Output "`n`n================================================================="
Write-Output "STALE USERS (No Activity > 6 Months)"
Write-Output "================================================================="
if ($staleUsers.Count -eq 0) {
    Write-Output "No stale users found."
} else {
    Write-Output "Count: $($staleUsers.Count)"
    Write-Output "Cutoff Date: $($sixMonthsAgo.ToString('MM/dd/yy'))"
    Write-Output "----------------------------------------"
    
    # Calculate column widths for Stale Users section
    $userIdWidth = [Math]::Max(($staleUsers | ForEach-Object { $_.UserId.Length } | Measure-Object -Maximum).Maximum, "User ID".Length) + 2
    $emailWidth = [Math]::Max(($staleUsers | ForEach-Object { $_.Email.Length } | Measure-Object -Maximum).Maximum, "Email".Length) + 2
    
    # Display headers
    $headerUserId = "User ID".PadRight($userIdWidth)
    $headerEmail = "Email".PadRight($emailWidth)
    Write-Output "  $headerUserId$headerEmail$("Last Activity")"
    Write-Output "  $("-" * ($userIdWidth-1)) $("-" * ($emailWidth-1)) $("-" * 13)"
    
    $staleUsers | Sort-Object LastActivity | ForEach-Object {
        $lastActivity = if ($_.LastActivity) { ([datetime]$_.LastActivity).ToString('MM/dd/yy') } else { "Never" }
        $formattedUserId = $_.UserId.PadRight($userIdWidth)
        $formattedEmail = $_.Email.PadRight($emailWidth)
        Write-Output "  $formattedUserId$formattedEmail$lastActivity"
    }
}

Write-Output "`n================================================================="
Write-Output "SUMMARY"
Write-Output "================================================================="
Write-Output "Total users with no employee record: $($noEmployeeRecord.Count)"
Write-Output "Total stale users: $($staleUsers.Count)"
Write-Output "Total active users processed: $($data.Count)"
Write-Output "Cutoff date for stale users: $($sixMonthsAgo.ToString('MM/dd/yy'))"