param(
    [string]$NewUserId
)

# Determine path to CSV (assumes Links-NewUser.csv sits alongside this script)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$csvPath   = Join-Path $scriptDir 'Add-NewUser-LinkWindow.csv'

if (-not (Test-Path $csvPath)) {
    Write-Error "Could not find file: $csvPath"
    return
}

# Import CSV entries
$entries = Import-Csv -Path $csvPath

# Build HTML content
$html = @()
$html += '<!DOCTYPE html>'
$html += '<html><head><meta charset="utf-8"><title>Quick Access Links</title>'
$html += '<style>'
$html += '  body { font-family: Segoe UI, sans-serif; padding: 20px; }'
$html += '  .btn {'
$html += '    display: inline-block;'
$html += '    margin: 8px;'
$html += '    padding: 10px 20px;'
$html += '    background-color: #0078D7;'
$html += '    color: #fff;'
$html += '    text-decoration: none;'
$html += '    border-radius: 4px;'
$html += '  }'
$html += '  .btn:hover { background-color: #005A9E; }'
$html += '</style>'
$html += '</head><body>'

foreach ($row in $entries) {
    # Replace literal "$NewUserId" in URL with the actual ID
    $url     = $row.URL.Replace('$NewUserId', $NewUserId)
    $title   = [System.Web.HttpUtility]::HtmlEncode($row.Title)
    $escaped = [System.Web.HttpUtility]::HtmlEncode($url)
    $html   += "  <a class='btn' href='$escaped' target='_blank'>$title</a><br />"
}

$html += '</body></html>'

# Save to a temp HTML file
$tempName = "NewUserLinks_$NewUserId.html"
$htmlPath = Join-Path ([IO.Path]::GetTempPath()) $tempName
$html -join "`n" | Out-File -FilePath $htmlPath -Encoding UTF8

# Open the HTML in default browser: use macOS 'open' if not Windows
if ($IsWindows) {
    Start-Process $htmlPath
} else {
    Start-Process -FilePath "open" -ArgumentList $htmlPath
}
