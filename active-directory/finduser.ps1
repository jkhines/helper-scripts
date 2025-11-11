Param(
    [Parameter(Mandatory)][string]$UsernameOrWWID
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

Function Get-OrgUnitGroups {
    param([String[]]$groupDNs, [Boolean]$isFirstGroup)
    
    if ($null -eq $groupDNs -or $groupDNs.Count -eq 0) {
        return
    }

    $groupDNs | ForEach-Object {
        if ($_.StartsWith("CN=ORGU")) {
            $groupDN = $_.Replace("(", "\28").Replace(")", "\29") # Escape open and closed parens.
            if ($Server) {
                $group = Get-ADGroup -LdapFilter "(&(objectCategory=group)(distinguishedName=$groupDN))" -Server $Server -Properties CN, MemberOf
            } else {
                $group = Get-ADGroup -LdapFilter "(&(objectCategory=group)(distinguishedName=$groupDN))" -Properties CN, MemberOf
            }

            if ($isFirstGroup) {
                "     {0}" -f $group.CN
            } else {
                "        in {0}" -f $group.CN
            }
            Get-OrgUnitGroups $group.MemberOf $false
        }
    }
}

$users = if ($UsernameOrWWID -match "\d{8}") { & "$PSScriptRoot\searchad.ps1" -WWID $UsernameOrWWID } else { & "$PSScriptRoot\searchad.ps1" -User $UsernameOrWWID }

$users | ForEach-Object {
    if ($_.MemberOf -match "CN=ORGU") {
        "{0} {1} (title={2}) {3} {4} {5}`n    Site: {6} {7} / Role: {8}`n  MEMBER of:" -f `
            $_.GivenName, $_.Surname, $_.jobDescription, $_.SamAccountName, `
            $_.EmployeeID, $_.UserPrincipalName

        Get-OrgUnitGroups $_.MemberOf $true
    }
}
