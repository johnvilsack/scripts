Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Get-CustomAppxPackages {
    Get-AppxPackage | Where-Object {
        -not $_.IsFramework -and $_.PublisherId -ne "cw5n1h2txyewy"
    } | Select-Object Name, PackageFullName
}

# Create Form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Appx Package Manager"
$form.Size = New-Object System.Drawing.Size(700, 500)
$form.StartPosition = "CenterScreen"

# Create a CheckedListBox
$listBox = New-Object System.Windows.Forms.CheckedListBox
$listBox.Size = New-Object System.Drawing.Size(660, 360)
$listBox.Location = New-Object System.Drawing.Point(10, 10)
$listBox.CheckOnClick = $true
$form.Controls.Add($listBox)

# Populate list
$packages = Get-CustomAppxPackages
foreach ($pkg in $packages) {
    $listBox.Items.Add($pkg.PackageFullName) | Out-Null
}

# Create Button
$removeButton = New-Object System.Windows.Forms.Button
$removeButton.Text = "Remove Selected"
$removeButton.Size = New-Object System.Drawing.Size(150, 40)
$removeButton.Location = New-Object System.Drawing.Point(10, 380)

# Button Click event
$removeButton.Add_Click({
    $selected = $listBox.CheckedItems
    if ($selected.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No packages selected.", "Info", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }

    $confirm = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to remove selected packages?", "Confirm Removal", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($confirm -eq "Yes") {
        foreach ($pkgName in $selected) {
            try {
                Write-Output "Removing $pkgName"
                Remove-AppxPackage -Package $pkgName -ErrorAction Stop
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Failed to remove $pkgName.`nError: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
        }
        [System.Windows.Forms.MessageBox]::Show("Selected packages have been removed (if applicable).", "Done", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        $form.Close()
    }
})

$form.Controls.Add($removeButton)

# Show the form
[void]$form.ShowDialog()