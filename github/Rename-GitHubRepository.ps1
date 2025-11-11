<#
.SYNOPSIS
    Renames a GitHub repository using the GitHub CLI.

.DESCRIPTION
    This script utilizes the 'gh' command-line tool to rename a specified GitHub repository.
    It includes prerequisite checks for 'gh' installation and authentication.

    Because renaming a repository is a significant action that can break existing clones, forks, and URLs,
    the script will prompt for confirmation by default. This confirmation can be bypassed using the -Force switch.

.PARAMETER FullName
    The current full name of the repository to rename, including the owner.
    (Required)
    Example: "my-username/old-repo-name"

.PARAMETER NewName
    The desired new name for the repository (without the owner).
    (Required)
    Example: "new-repo-name"

.PARAMETER Force
    A switch to bypass the confirmation prompt and immediately rename the repository.

.EXAMPLE
    PS C:\> .\Rename-GitHubRepo.ps1 -FullName "my-username/project-alpha" -NewName "project-omega"

    This command will prompt for confirmation before renaming the "project-alpha" repository to "project-omega".
    > Confirm
    > Are you sure you want to perform this action?
    > Performing the operation "Rename repository to 'project-omega'" on target "my-username/project-alpha".
    > [Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "Y"): Y
    > SUCCESS: Repository 'my-username/project-alpha' has been successfully renamed to 'my-username/project-omega'.

.EXAMPLE
    PS C:\> .\Rename-GitHubRepo.ps1 -FullName "my-org/data-processor" -NewName "data-pipeline" -Force

    This command renames the repository immediately without asking for confirmation.

.NOTES
    Author: Your Name
    Prerequisites:
    1. PowerShell 5.1 or later.
    2. GitHub CLI ('gh') must be installed and in your system's PATH.
    3. You must be authenticated with the GitHub CLI (`gh auth login`).
    4. The authenticated user must have admin permissions on the target repository to rename it.

    Important: GitHub automatically sets up redirects from the old repository URL to the new one. However,
    it is best practice to update any local clones to point to the new remote URL.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, HelpMessage = "The current full name of the repository in 'owner/repo' format.")]
    [string]$FullName,

    [Parameter(Mandatory = $true, HelpMessage = "The new name for the repository (name only, not the full path).")]
    [string]$NewName,

    [Parameter(HelpMessage = "Bypass the confirmation prompt for renaming.")]
    [switch]$Force
)

# --- Prerequisite Checks ---
try {
    # 1. Check if 'gh' CLI is installed
    Write-Verbose "Checking for GitHub CLI ('gh') installation..."
    $ghPath = Get-Command gh -ErrorAction Stop
    Write-Verbose "GitHub CLI found at: $($ghPath.Source)"

    # 2. Check if user is logged in
    Write-Verbose "Checking GitHub CLI authentication status..."
    gh auth status -h github.com -t 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "You are not logged into the GitHub CLI. Please run 'gh auth login' and try again."
    }
    Write-Verbose "User is authenticated with GitHub CLI."
}
catch {
    Write-Error "Prerequisite check failed: $_"
    # Exit the script because it cannot continue
    return
}

# --- Main Logic ---
try {
    # Validate that the new name doesn't contain a slash
    if ($NewName -like "*/*" -or $NewName -like "*\*") {
        throw "The new repository name '$NewName' is invalid. It should not contain slashes."
    }

    Write-Host "INFO: Preparing to rename repository '$FullName' to '$NewName'..."

    # Use ShouldProcess for -Confirm and -WhatIf support
    $action = "Rename repository to '$NewName'"
    $target = $FullName
    
    if ($PSCmdlet.ShouldProcess($target, $action) -or $Force) {
        Write-Host "Attempting to execute rename operation..."
        
        # The 'gh' CLI has its own confirmation prompt. The '--yes' flag bypasses it,
        # which is what we want since PowerShell is already handling confirmation.
        # We capture all output streams to get error details if it fails.
        $renameOutput = gh repo rename $NewName --repo $FullName --yes 2>&1 | Out-String
        
        if ($LASTEXITCODE -eq 0) {
            # Extract the owner from the original FullName to construct the new full name for the message
            $owner = ($FullName -split '/')[0]
            Write-Host -ForegroundColor Green "SUCCESS: Repository '$FullName' has been successfully renamed to '$owner/$NewName'."
            Write-Host "INFO: Remember to update the remote URL in any local clones:"
            Write-Host "  git remote set-url origin git@github.com:$owner/$NewName.git"
        }
        else {
            # Throw an error with the captured output from the gh command
            throw "Failed to rename repository. GitHub CLI returned an error: `n$renameOutput"
        }
    }
    else {
        Write-Warning "Action cancelled by user. Repository '$FullName' was not renamed."
    }
}
catch {
    Write-Error "An error occurred during the renaming process: $_"
}
