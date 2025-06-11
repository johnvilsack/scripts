# --- Force Windows Update scan, download and install ---
# 1. Create Update Session and Searcher
$session = New-Object -ComObject Microsoft.Update.Session
$searcher = $session.CreateUpdateSearcher()

# 2. Find all software updates not yet installed
$results = $searcher.Search("IsInstalled=0 and Type='Software'")

if ($results.Updates.Count -gt 0) {
    # 3. Collect updates to install
    $collection = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($update in $results.Updates) {
        $collection.Add($update) | Out-Null
    }

    # 4. Install them
    $installer = $session.CreateUpdateInstaller()
    $installer.Updates = $collection
    $installResult = $installer.Install()

    # 5. Reboot if required
    if ($installResult.RebootRequired) {
        Restart-Computer -Force
    }
}
