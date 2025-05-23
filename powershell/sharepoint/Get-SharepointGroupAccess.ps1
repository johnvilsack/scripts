# Connect to SharePoint
Connect-SPOService -Url https://shipperssupply-admin.sharepoint.com

# Replace this with your group name
$targetGroup = "Shippers All Staff"

# Get all sites
$sites = Get-SPOSite -Limit All

foreach ($site in $sites) {
    $web = Get-SPOSite -Identity $site.Url
    try {
        $ctx = New-Object Microsoft.SharePoint.Client.ClientContext($site.Url)
        $ctx.Credentials = (Get-Credential)
        $web = $ctx.Web
        $ctx.Load($web.RoleAssignments)
        $ctx.ExecuteQuery()

        foreach ($roleAssignment in $web.RoleAssignments) {
            $member = $roleAssignment.Member
            $ctx.Load($member)
            $ctx.ExecuteQuery()
            if ($member.Title -eq $targetGroup) {
                Write-Output "$($site.Url): $($member.Title) has permissions"
            }
        }
    } catch {
        Write-Warning "Failed to check $($site.Url)"
    }
}