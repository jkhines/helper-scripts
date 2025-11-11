Param(
    [Parameter(Mandatory)][string]$UsernameOrWWID
)
Import-Module ActiveDirectory

$users = if ($UsernameOrWWID -match "\d{8}") { searchad -WWID $UsernameOrWWID } else { searchad -User $UsernameOrWWID }

$users | Select-Object -Property Name,SamAccountName,UserPrincipalName,EmployeeID | `
    Sort-Object -Property Name | Format-Table
