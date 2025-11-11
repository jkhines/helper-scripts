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

$managerDN = $(& "$PSScriptRoot\searchad.ps1" -User $Username).manager

if ($null -ne $managerDN) {
    if ($Server) {
        Get-ADUser -LdapFilter "(&(objectCategory=person)(distinguishedName=$managerDN))" -Server $Server | `
            Select-Object -Property Name,SamAccountName,UserPrincipalName
    } else {
        Get-ADUser -LdapFilter "(&(objectCategory=person)(distinguishedName=$managerDN))" | `
            Select-Object -Property Name,SamAccountName,UserPrincipalName
    }
}
