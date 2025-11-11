Param(
    [Parameter(Mandatory)][string]$Groupname
)
Import-Module ActiveDirectory

# Determine the AD server to use.
$Server = $null
try {
    Get-ADDomain -ErrorAction Stop | Out-Null
} catch {
    try {
        $domain = Get-ADDomain -ErrorAction Stop
        $Server = "$($domain.PDCEmulator):3268"
        Get-ADDomain -Server $Server -ErrorAction Stop | Out-Null
    } catch {
        throw 'Active Directory is unreachable. Connect to VPN.'
    }
}

$group = & "$PSScriptRoot\searchad.ps1" -Group $Groupname

Write-Host "Group" $group.Name "has" $group.Members.Count "members"
if ($group.Members.Count -ne 0) {
    $group.Members | ForEach-Object { $dnFilter += "(distinguishedName=$_)" }
    if ($Server) {
        Get-ADObject -LdapFilter "(|$dnFilter)" -Server $Server -Properties Name,SamAccountName,ObjectClass | `
            Select-Object -Property Name,SamAccountName,ObjectClass | `
                Sort-Object -Property ObjectClass,Name
    } else {
        Get-ADObject -LdapFilter "(|$dnFilter)" -Properties Name,SamAccountName,ObjectClass | `
            Select-Object -Property Name,SamAccountName,ObjectClass | `
                Sort-Object -Property ObjectClass,Name
    }
}
