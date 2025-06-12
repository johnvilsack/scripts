<#
.SYNOPSIS
  Retrieves users via Acumatica OData and displays grouped results on screen.

.DESCRIPTION
  - Reads ACU_USERNAME/ACU_PASSWORD from a `.acumatica.env` file located alongside this script.
  - Calls the `_JV-GetEmployees` endpoint with Basic Auth and requests JSON.
  - Groups TEMPS by SupervisorEmail and Contractors/ITECH/SYSTEM by SupervisorEmail.
  - Displays the groupings on screen.

.EXAMPLE
  PS> .\Audit-Employees.ps1
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
$uri = 'https://shippers-supply.acumatica.com/odata/Shippers%20Supply/_JV-GetEmployees?$filter=EmployeeStatus%20eq%20''Active''%20and%20PositionStatus%20eq%20true&$select=Login,EmployeeName,Email,SupervisorEmail,EmployeeClass,Position,LastActivity'
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

# Filter and group each category separately by SupervisorEmail
$temps = $data | Where-Object { $_.EmployeeClass -eq 'TEMPS' } | Group-Object SupervisorEmail
$contractors = $data | Where-Object { $_.Position -eq 'Contractor' } | Group-Object SupervisorEmail
$itech = $data | Where-Object { $_.Position -eq 'ITECH' } | Group-Object SupervisorEmail
$system = $data | Where-Object { $_.Position -eq 'SYSTEM' } | Group-Object SupervisorEmail

# Display TEMPS groupings
Write-Output "================================================================="
Write-Output "TEMPS EMPLOYEES GROUPED BY SUPERVISOR"
Write-Output "================================================================="
if ($temps.Count -eq 0) {
    Write-Output "No TEMPS employees found."
} else {
    foreach ($group in $temps) {
        $supervisorName = if ([string]::IsNullOrWhiteSpace($group.Name)) { "(No Supervisor Assigned)" } else { $group.Name }
        Write-Output "`nSupervisor: $supervisorName"
        Write-Output "Count: $($group.Count)"
        Write-Output "----------------------------------------"
        
        # Calculate column widths for this group
        $nameWidth = [Math]::Max(($group.Group | ForEach-Object { $_.EmployeeName.Length } | Measure-Object -Maximum).Maximum, "Name".Length) + 2
        $loginWidth = [Math]::Max(($group.Group | ForEach-Object { "($($_.Login))".Length } | Measure-Object -Maximum).Maximum, "Login".Length) + 2
        $emailWidth = [Math]::Max(($group.Group | ForEach-Object { $_.Email.Length } | Measure-Object -Maximum).Maximum, "Email".Length) + 2
        
        # Display headers
        $headerName = "Name".PadRight($nameWidth)
        $headerLogin = "Login".PadRight($loginWidth)
        $headerEmail = "Email".PadRight($emailWidth)
        Write-Output "  $headerName$headerLogin$headerEmail$("Last Active")"
        Write-Output "  $("-" * ($nameWidth-1)) $("-" * ($loginWidth-1)) $("-" * ($emailWidth-1)) $("-" * 11)"
        
        $group.Group | ForEach-Object {
            $lastActivity = if ($_.LastActivity) { ([datetime]$_.LastActivity).ToString('MM/dd/yy') } else { "Never" }
            $formattedName = $_.EmployeeName.PadRight($nameWidth)
            $formattedLogin = "($($_.Login))".PadRight($loginWidth)
            $formattedEmail = $_.Email.PadRight($emailWidth)
            Write-Output "  $formattedName$formattedLogin$formattedEmail$lastActivity"
        }
    }
}

# Display Contractor groupings
Write-Output "`n`n================================================================="
Write-Output "CONTRACTOR EMPLOYEES GROUPED BY SUPERVISOR"
Write-Output "================================================================="
if ($contractors.Count -eq 0) {
    Write-Output "No Contractor employees found."
} else {
    foreach ($group in $contractors) {
        $supervisorName = if ([string]::IsNullOrWhiteSpace($group.Name)) { "(No Supervisor Assigned)" } else { $group.Name }
        Write-Output "`nSupervisor: $supervisorName"
        Write-Output "Count: $($group.Count)"
        Write-Output "----------------------------------------"
        
        # Calculate column widths for this group
        $nameWidth = [Math]::Max(($group.Group | ForEach-Object { $_.EmployeeName.Length } | Measure-Object -Maximum).Maximum, "Name".Length) + 2
        $loginWidth = [Math]::Max(($group.Group | ForEach-Object { "($($_.Login))".Length } | Measure-Object -Maximum).Maximum, "Login".Length) + 2
        $emailWidth = [Math]::Max(($group.Group | ForEach-Object { $_.Email.Length } | Measure-Object -Maximum).Maximum, "Email".Length) + 2
        
        # Display headers
        $headerName = "Name".PadRight($nameWidth)
        $headerLogin = "Login".PadRight($loginWidth)
        $headerEmail = "Email".PadRight($emailWidth)
        Write-Output "  $headerName$headerLogin$headerEmail$("Last Active")"
        Write-Output "  $("-" * ($nameWidth-1)) $("-" * ($loginWidth-1)) $("-" * ($emailWidth-1)) $("-" * 11)"
        
        $group.Group | ForEach-Object {
            $lastActivity = if ($_.LastActivity) { ([datetime]$_.LastActivity).ToString('MM/dd/yy') } else { "Never" }
            $formattedName = $_.EmployeeName.PadRight($nameWidth)
            $formattedLogin = "($($_.Login))".PadRight($loginWidth)
            $formattedEmail = $_.Email.PadRight($emailWidth)
            Write-Output "  $formattedName$formattedLogin$formattedEmail$lastActivity"
        }
    }
}

# Display ITECH groupings
Write-Output "`n`n================================================================="
Write-Output "ITECH EMPLOYEES GROUPED BY SUPERVISOR"
Write-Output "================================================================="
if ($itech.Count -eq 0) {
    Write-Output "No ITECH employees found."
} else {
    foreach ($group in $itech) {
        $supervisorName = if ([string]::IsNullOrWhiteSpace($group.Name)) { "(No Supervisor Assigned)" } else { $group.Name }
        Write-Output "`nSupervisor: $supervisorName"
        Write-Output "Count: $($group.Count)"
        Write-Output "----------------------------------------"
        
        # Calculate column widths for this group
        $nameWidth = [Math]::Max(($group.Group | ForEach-Object { $_.EmployeeName.Length } | Measure-Object -Maximum).Maximum, "Name".Length) + 2
        $loginWidth = [Math]::Max(($group.Group | ForEach-Object { "($($_.Login))".Length } | Measure-Object -Maximum).Maximum, "Login".Length) + 2
        $emailWidth = [Math]::Max(($group.Group | ForEach-Object { $_.Email.Length } | Measure-Object -Maximum).Maximum, "Email".Length) + 2
        
        # Display headers
        $headerName = "Name".PadRight($nameWidth)
        $headerLogin = "Login".PadRight($loginWidth)
        $headerEmail = "Email".PadRight($emailWidth)
        Write-Output "  $headerName$headerLogin$headerEmail$("Last Active")"
        Write-Output "  $("-" * ($nameWidth-1)) $("-" * ($loginWidth-1)) $("-" * ($emailWidth-1)) $("-" * 11)"
        
        $group.Group | ForEach-Object {
            $lastActivity = if ($_.LastActivity) { ([datetime]$_.LastActivity).ToString('MM/dd/yy') } else { "Never" }
            $formattedName = $_.EmployeeName.PadRight($nameWidth)
            $formattedLogin = "($($_.Login))".PadRight($loginWidth)
            $formattedEmail = $_.Email.PadRight($emailWidth)
            Write-Output "  $formattedName$formattedLogin$formattedEmail$lastActivity"
        }
    }
}

# Display SYSTEM groupings
Write-Output "`n`n================================================================="
Write-Output "SYSTEM EMPLOYEES GROUPED BY SUPERVISOR"
Write-Output "================================================================="
if ($system.Count -eq 0) {
    Write-Output "No SYSTEM employees found."
} else {
    foreach ($group in $system) {
        $supervisorName = if ([string]::IsNullOrWhiteSpace($group.Name)) { "(No Supervisor Assigned)" } else { $group.Name }
        Write-Output "`nSupervisor: $supervisorName"
        Write-Output "Count: $($group.Count)"
        Write-Output "----------------------------------------"
        
        # Calculate column widths for this group
        $nameWidth = [Math]::Max(($group.Group | ForEach-Object { $_.EmployeeName.Length } | Measure-Object -Maximum).Maximum, "Name".Length) + 2
        $loginWidth = [Math]::Max(($group.Group | ForEach-Object { "($($_.Login))".Length } | Measure-Object -Maximum).Maximum, "Login".Length) + 2
        $emailWidth = [Math]::Max(($group.Group | ForEach-Object { $_.Email.Length } | Measure-Object -Maximum).Maximum, "Email".Length) + 2
        
        # Display headers
        $headerName = "Name".PadRight($nameWidth)
        $headerLogin = "Login".PadRight($loginWidth)
        $headerEmail = "Email".PadRight($emailWidth)
        Write-Output "  $headerName$headerLogin$headerEmail$("Last Active")"
        Write-Output "  $("-" * ($nameWidth-1)) $("-" * ($loginWidth-1)) $("-" * ($emailWidth-1)) $("-" * 11)"
        
        $group.Group | ForEach-Object {
            $lastActivity = if ($_.LastActivity) { ([datetime]$_.LastActivity).ToString('MM/dd/yy') } else { "Never" }
            $formattedName = $_.EmployeeName.PadRight($nameWidth)
            $formattedLogin = "($($_.Login))".PadRight($loginWidth)
            $formattedEmail = $_.Email.PadRight($emailWidth)
            Write-Output "  $formattedName$formattedLogin$formattedEmail$lastActivity"
        }
    }
}

Write-Output "`n================================================================="
Write-Output "SUMMARY"
Write-Output "================================================================="
Write-Output "Total TEMPS employees: $(($temps | Measure-Object -Property Count -Sum).Sum)"
Write-Output "Total Contractor employees: $(($contractors | Measure-Object -Property Count -Sum).Sum)"
Write-Output "Total ITECH employees: $(($itech | Measure-Object -Property Count -Sum).Sum)"
Write-Output "Total SYSTEM employees: $(($system | Measure-Object -Property Count -Sum).Sum)"
Write-Output "Total records processed: $($data.Count)"