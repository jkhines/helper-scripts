<#
.SYNOPSIS
Search Active Directory for a user, WWID, group, or computer.
#>
[CmdletBinding(DefaultParameterSetName='UserName')]
param(
    [Parameter(Mandatory,ParameterSetName='UserName',Position=0)]
    [string] $User,
    [Parameter(Mandatory,ParameterSetName='UserId',Position=0)]
    [int] $WWID,
    [Parameter(Mandatory,ParameterSetName='GroupName',Position=0)]
    [string] $Group,
    [Parameter(Mandatory,ParameterSetName='ComputerName',Position=0)]
    [string] $Computer,
    [string] $Server
)

Set-StrictMode -Version Latest

# Escape LDAP filter special characters.
function Escape-LdapFilter {
    param([string] $InputString)
    $InputString -replace '\\','\\5c' -replace '\*','\\2a' -replace '\(','\\28' -replace '\)','\\29' -replace "`0",'\\00'
}

try { Import-Module ActiveDirectory -ErrorAction Stop }
catch { throw 'Missing ActiveDirectory module. Install RSAT tools.' }

# Determine the AD server to use if not explicitly provided.
if (-not $Server) {
    try {
        # First, try default AD discovery (works on corporate network).
        Get-ADDomain -ErrorAction Stop | Out-Null
    } catch {
        # If default fails, try to use Global Catalog (needed for VPN/off-network).
        try {
            $domain = Get-ADDomain -ErrorAction Stop
            $Server = "$($domain.PDCEmulator):3268"
            Get-ADDomain -Server $Server -ErrorAction Stop | Out-Null
        } catch {
            throw 'Active Directory is unreachable. Connect to VPN.'
        }
    }
} else {
    # Verify the explicitly provided server is accessible.
    try {
        Get-ADDomain -Server $Server -ErrorAction Stop | Out-Null
    } catch {
        throw "Unable to connect to Active Directory server $Server. $_"
    }
}

switch ($PSCmdlet.ParameterSetName) {
    'UserName' {
        $safeUser = Escape-LdapFilter $User
        if ($Server) {
            Get-ADUser -Filter "sAMAccountName -eq '$safeUser'" -Server $Server -Properties *
        } else {
            Get-ADUser -Filter "sAMAccountName -eq '$safeUser'" -Properties *
        }
    }
    'UserId' {
        if ($Server) {
            Get-ADUser -Filter "employeeID -eq '$WWID'" -Server $Server -Properties *
        } else {
            Get-ADUser -Filter "employeeID -eq '$WWID'" -Properties *
        }
    }
    'GroupName' {
        $safeGroup = Escape-LdapFilter $Group
        if ($Server) {
            Get-ADGroup -Filter "sAMAccountName -eq '$safeGroup'" -Server $Server -Properties *
        } else {
            Get-ADGroup -Filter "sAMAccountName -eq '$safeGroup'" -Properties *
        }
    }
    'ComputerName' {
        $safeComputer = Escape-LdapFilter $Computer
        if ($Server) {
            Get-ADComputer -Filter "sAMAccountName -eq '$safeComputer$'" -Server $Server -Properties *
        } else {
            Get-ADComputer -Filter "sAMAccountName -eq '$safeComputer$'" -Properties *
        }
    }
}
