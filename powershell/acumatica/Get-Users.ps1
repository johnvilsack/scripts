<#
.SYNOPSIS
  Retrieves users via Acumatica OData and exports them to CSV.

.DESCRIPTION
  - Reads ACU_USERNAME/ACU_PASSWORD from a `.acumatica.env` file located alongside this script.
  - Calls the `_JV-GetUsers` endpoint with Basic Auth and requests JSON.
  - Exports the returned `.value` array to `Get-Users.csv` in the same folder.

.EXAMPLE
  PS> .\Get-Users.ps1
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
$uri = 'https://shippers-supply.acumatica.com/odata/Shippers%20Supply/_JV-GetUsers'
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

# -- Export to CSV --
$csvPath = Join-Path $PSScriptRoot 'Get-Users.csv'
$data | Export-Csv -Path $csvPath -NoTypeInformation

Write-Output "Exported $($data.Count) records to CSV: $csvPath"
