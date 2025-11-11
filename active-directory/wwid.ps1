Param(
	[Parameter(Mandatory)][string]$Username
)
Import-Module ActiveDirectory

searchad -User $Username | Select-Object -Property SamAccountName,EmployeeID
