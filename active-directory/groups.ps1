Param(
    [Parameter(Mandatory)][string]$Username
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

$user = & "$PSScriptRoot\searchad.ps1" -User $Username

if ($user.MemberOf.Count -ne 0) {
    $user.MemberOf | ForEach-Object { $dnFilter += "(distinguishedName=$_)" }
    if ($Server) {
        Get-ADGroup -LdapFilter "(&(objectCategory=group)(|$dnFilter))" -Server $Server | `
            Select-Object -Property Name,GroupCategory,GroupScope | `
                Sort-Object -Property Name
    } else {
        Get-ADGroup -LdapFilter "(&(objectCategory=group)(|$dnFilter))" | `
            Select-Object -Property Name,GroupCategory,GroupScope | `
                Sort-Object -Property Name
    }
}
