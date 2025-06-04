$Username = "LAPSAdminSSI"
$Password = "Bacon-crib-vice-spray-61#"  # Temporary, will be replaced by LAPS

# Check if user exists
if (-not (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue)) {
    # Create user
    $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
    New-LocalUser -Name $Username -Password $securePassword -FullName "LAPS Admin SSI" -Description "Local admin managed by LAPS"
    
    # Add to Administrators group
    Add-LocalGroupMember -Group "Administrators" -Member $Username
}
