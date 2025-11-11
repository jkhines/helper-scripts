Param(
    [Parameter(Mandatory)][string]$UsernameOrWWID
)
Import-Module ActiveDirectory

$users = if ($UsernameOrWWID -match "\d{8}") { searchad -WWID $UsernameOrWWID } else { searchad -User $UsernameOrWWID }

$users | Where-Object { $null -ne $_.pwdLastSet } | `
    Select-Object -Property SamAccountName,@{Name = 'PasswordExpirationDate'; Expression = {[DateTime]::FromFileTime($_.pwdLastSet).AddDays(90)}},PasswordNeverExpires | `
        Sort-Object -Property PasswordExpirationDate
