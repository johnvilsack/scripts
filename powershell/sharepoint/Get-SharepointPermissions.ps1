#Requires -Module PnP.PowerShell

# --- CONFIGURATION ---
$siteUrl = "YOUR_SHAREPOINT_SITE_URL_HERE" # e.g., "https://yourtenant.sharepoint.com/sites/yourclassicsite"
$outputCsvPath = "C:\Temp\SharePointPermissionsAudit.csv" # Ensure C:\Temp exists or change path
# --- END CONFIGURATION ---

# Array to hold permission data
$permissionsReport = @()

Function Get-ItemPermissions {
    param (
        [Parameter(Mandatory=$true)]
        [PnP.PowerShell.Commands.Base.PnPConnectedCmdletBase]$Cmdlet, # Pass the current cmdlet context
        [Parameter(Mandatory=$true)]
        $Item, # List, Folder, or Web object
        [Parameter(Mandatory=$true)]
        [string]$ItemType, # "Site", "Library/List", "Folder"
        [Parameter(Mandatory=$true)]
        [string]$ItemName,
        [Parameter(Mandatory=$true)]
        [string]$ItemUrl,
        [string]$ParentListName = "" # Optional, for folders
    )

    Write-Host "    Fetching permissions for $ItemType: $ItemName" -ForegroundColor Cyan
    # Ensure RoleAssignments are loaded
    $Cmdlet.ClientContext.Load($Item.RoleAssignments)
    $Cmdlet.ClientContext.ExecuteQueryRetry()

    foreach ($roleAssignment in $Item.RoleAssignments) {
        # Ensure Member and RoleDefinitionBindings are loaded
        $Cmdlet.ClientContext.Load($roleAssignment.Member)
        $Cmdlet.ClientContext.Load($roleAssignment.RoleDefinitionBindings)
        $Cmdlet.ClientContext.ExecuteQueryRetry()

        $principal = $roleAssignment.Member
        foreach ($roleDefinition in $roleAssignment.RoleDefinitionBindings) {
            $permissionsReport += [PSCustomObject]@{
                ItemType          = $ItemType
                ItemName          = $ItemName
                ItemUrl           = $ItemUrl
                ParentList        = $ParentListName
                InheritanceBroken = $Item.HasUniqueRoleAssignments # Should always be true if we are here
                PrincipalType     = $principal.PrincipalType
                PrincipalName     = $principal.Title # Or $principal.LoginName for more detail
                PermissionLevel   = $roleDefinition.Name
            }
        }
    }
}

Function Get-FolderPermissionsRecursive {
    param (
        [Parameter(Mandatory=$true)]
        [PnP.PowerShell.Commands.Base.PnPConnectedCmdletBase]$Cmdlet,
        [Parameter(Mandatory=$true)]
        [Microsoft.SharePoint.Client.Folder]$ParentFolder,
        [Parameter(Mandatory=$true)]
        [string]$ListTitle,
        [Parameter(Mandatory=$true)]
        [string]$SiteBaseUrl # To construct full URLs
    )

    # Get subfolders
    $Cmdlet.ClientContext.Load($ParentFolder.Folders)
    $Cmdlet.ClientContext.ExecuteQueryRetry()

    foreach ($folder in $ParentFolder.Folders) {
        # Ensure HasUniqueRoleAssignments is loaded for the folder
        $Cmdlet.ClientContext.Load($folder, "HasUniqueRoleAssignments", "Name", "ServerRelativeUrl")
        $Cmdlet.ClientContext.ExecuteQueryRetry()

        $folderFullUrl = "$SiteBaseUrl$($folder.ServerRelativeUrl)"
        Write-Host "  Checking Folder: $($folder.Name) in list '$ListTitle'"

        if ($folder.HasUniqueRoleAssignments) {
            Write-Host "  -> Folder '$($folder.Name)' has unique permissions." -ForegroundColor Yellow
            Get-ItemPermissions -Cmdlet $Cmdlet -Item $folder -ItemType "Folder" -ItemName $folder.Name -ItemUrl $folderFullUrl -ParentListName $ListTitle
        }

        # Recurse
        Get-FolderPermissionsRecursive -Cmdlet $Cmdlet -ParentFolder $folder -ListTitle $ListTitle -SiteBaseUrl $SiteBaseUrl
    }
}

try {
    Write-Host "Connecting to SharePoint site: $siteUrl"
    # -Interactive will prompt for login. For unattended, explore other auth methods (e.g., -Credentials, App-Only)
    Connect-PnPOnline -Url $siteUrl -Interactive
    $currentCmdlet = $PSCmdlet # Get current cmdlet context for passing to functions

    $web = Get-PnPWeb -Includes HasUniqueRoleAssignments, Title, Url, ServerRelativeUrl
    $siteBaseUrl = $web.Url.Replace($web.ServerRelativeUrl, "") # Get the base URL like https://tenant.sharepoint.com

    Write-Host "Auditing Site Level: $($web.Title)"
    if ($web.HasUniqueRoleAssignments) { # Root web always has unique permissions technically
        Get-ItemPermissions -Cmdlet $currentCmdlet -Item $web -ItemType "Site" -ItemName $web.Title -ItemUrl $web.Url
    } else {
         # This case is unlikely for the root web itself, more for subwebs if you extend the script
        Write-Host "Site $($web.Title) inherits permissions (This is normal for the root)."
    }

    $lists = Get-PnPList -Includes HasUniqueRoleAssignments, Title, RootFolder, DefaultViewUrl, Hidden
    Write-Host "Found $($lists.Count) lists/libraries. Auditing..."

    foreach ($list in $lists) {
        if ($list.Hidden -eq $false) { # Skip hidden lists (e.g., system lists)
            $listFullUrl = "$siteBaseUrl$($list.DefaultViewUrl)" # Construct a full URL to the list
            Write-Host "Processing Library/List: $($list.Title)"

            if ($list.HasUniqueRoleAssignments) {
                Write-Host "-> Library/List '$($list.Title)' has unique permissions." -ForegroundColor Green
                Get-ItemPermissions -Cmdlet $currentCmdlet -Item $list -ItemType "Library/List" -ItemName $list.Title -ItemUrl $listFullUrl
            }

            # Now check folders within this list, regardless of list's own inheritance.
            # A list might inherit, but a folder within it might break inheritance.
            Write-Host "  Checking folders in '$($list.Title)'..."
            # Ensure RootFolder is loaded with necessary properties for recursion
            $Cmdlet.ClientContext.Load($list.RootFolder)
            $Cmdlet.ClientContext.ExecuteQueryRetry()
            Get-FolderPermissionsRecursive -Cmdlet $currentCmdlet -ParentFolder $list.RootFolder -ListTitle $list.Title -SiteBaseUrl $siteBaseUrl
        } else {
            Write-Host "Skipping hidden list: $($list.Title)" -ForegroundColor Gray
        }
    }

    if ($permissionsReport.Count -gt 0) {
        Write-Host "Exporting report to $outputCsvPath"
        $permissionsReport | Export-Csv -Path $outputCsvPath -NoTypeInformation -Encoding UTF8
        Write-Host "Audit complete. Report saved to $outputCsvPath" -ForegroundColor Green
    } else {
        Write-Host "No items with explicitly broken inheritance (beyond the root site) were found or processed." -ForegroundColor Yellow
    }

}
catch {
    Write-Error "An error occurred: $($_.Exception.Message)"
    Write-Error "Stack Trace: $($_.ScriptStackTrace)"
}
finally {
    if (Get-PnPConnection -ErrorAction SilentlyContinue) {
        Write-Host "Disconnecting from SharePoint site."
        Disconnect-PnPOnline
    }
}