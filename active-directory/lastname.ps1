Param(
    [Parameter(Mandatory)][string]$Surname
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

if ($Server) {
    Get-ADUser -LdapFilter "(&(objectCategory=person)(sn=$Surname))" -Server $Server | `
        Select-Object -Property GivenName,SamAccountName,UserPrincipalName | `
            Sort-Object -Property GivenName
} else {
    Get-ADUser -LdapFilter "(&(objectCategory=person)(sn=$Surname))" | `
        Select-Object -Property GivenName,SamAccountName,UserPrincipalName | `
            Sort-Object -Property GivenName
}
