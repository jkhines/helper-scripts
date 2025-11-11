<#
.SYNOPSIS
    Checks if a GitHub repository is public and, if so, converts it to private using the GitHub CLI.

.DESCRIPTION
    This script uses the 'gh' command-line tool to inspect a GitHub repository specified in the 'owner/repo' format.
    It first verifies that the GitHub CLI is installed and that the user is authenticated.
    
    It then retrieves the repository's visibility status. If the repository is public, it will prompt the user
    for confirmation before changing its visibility to private. The confirmation can be bypassed with the -Force switch.
    If the repository is already private or internal, it will report the current status and take no action.

.PARAMETER OwnerAndRepo
    The repository identifier. Can be either:
    - Repository name in 'owner/repo' format (e.g., "my-username/my-awesome-project")
    - Full GitHub URL (e.g., "https://github.com/my-username/my-awesome-project.git")
    (Required)

.PARAMETER Force
    A switch to bypass the confirmation prompt and immediately convert the public repository to private.

.EXAMPLE
    PS C:\> .\Convert-PublicRepoToPrivate.ps1 -OwnerAndRepo "my-username/my-public-repo"

    This command will check the visibility of "my-username/my-public-repo". If it's public, it will ask for
    confirmation before making it private.
    > Confirm
    > Are you sure you want to perform this action?
    > Performing the operation "Convert from Public to Private" on target "Repository 'my-username/my-public-repo'".
    > [Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "Y"): Y
    > INFO: Repository 'my-username/my-public-repo' is public. Attempting to convert to private...
    > SUCCESS: Repository 'my-username/my-public-repo' has been successfully converted to private.

.EXAMPLE
    PS C:\> .\Convert-PublicRepoToPrivate.ps1 -OwnerAndRepo "my-org/a-private-repo"

    This command will check the repository and find that it is already private, taking no action.
    > INFO: Repository 'my-org/a-private-repo' is already private. No action needed.

.EXAMPLE
    PS C:\> .\Convert-PublicRepoToPrivate.ps1 -OwnerAndRepo "my-username/my-public-repo" -Force

    This command will check the repository and, if public, convert it to private immediately
    without asking for confirmation.

.EXAMPLE
    PS C:\> .\Convert-PublicRepoToPrivate.ps1 -OwnerAndRepo "https://github.com/my-username/my-public-repo.git"

    This command accepts a full GitHub URL and will convert it to the proper format before
    checking the repository visibility.

.NOTES
    Author: Your Name
    Prerequisites:
    1. PowerShell 5.1 or later.
    2. GitHub CLI ('gh') must be installed and in your system's PATH.
    3. You must be authenticated with the GitHub CLI (`gh auth login`).
    4. The authenticated user must have admin permissions on the target repository to change its visibility.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, HelpMessage = "The repository name in 'owner/repo' format.")]
    [string]$OwnerAndRepo,

    [Parameter(HelpMessage = "Bypass the confirmation prompt.")]
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
    # Exit the script because it cannot continue without the prerequisites
    return
}

# --- Main Logic ---
try {
    # Convert GitHub URL to owner/repo format if needed
    if ($OwnerAndRepo -match "^https?://github\.com/([^/]+/[^/]+)(?:\.git)?/?$") {
        $OwnerAndRepo = $matches[1]
        # Remove .git extension if it's still there
        $OwnerAndRepo = $OwnerAndRepo -replace '\.git$', ''
        Write-Verbose "Converted GitHub URL to repository format: $OwnerAndRepo"
    }
    
    Write-Host "INFO: Fetching visibility status for repository '$OwnerAndRepo'..."
    
    # Use 'gh repo view' with the --json flag to get structured data
    # Redirect stderr to null to suppress 'gh' progress messages
    $repoInfoJson = gh repo view $OwnerAndRepo --json visibility 2>$null
    
    # Check if the command failed (e.g., repo not found, no permissions)
    if ($LASTEXITCODE -ne 0) {
        # Attempt to get a more specific error from gh
        $errorDetails = gh repo view $OwnerAndRepo 2>&1 | Out-String
        throw "Failed to get repository information. Error: $errorDetails"
    }

    # Convert the JSON output to a PowerShell object
    $repoInfo = $repoInfoJson | ConvertFrom-Json

    # Check the visibility and take action
    switch ($repoInfo.visibility.ToLower()) {
        "public" {
            Write-Host "INFO: Repository '$OwnerAndRepo' is public. Attempting to convert to private..."

            # Use ShouldProcess for -Confirm and -WhatIf support
            $action = "Convert from Public to Private"
            $target = "Repository '$OwnerAndRepo'"
            
            if ($PSCmdlet.ShouldProcess($target, $action) -or $Force) {
                # Execute the command to change visibility
                gh repo edit $OwnerAndRepo --visibility private --accept-visibility-change-consequences
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host -ForegroundColor Green "SUCCESS: Repository '$OwnerAndRepo' has been successfully converted to private."
                }
                else {
                    throw "The 'gh repo edit' command failed. You may not have sufficient permissions."
                }
            }
            else {
                Write-Warning "Action cancelled by user. Repository '$OwnerAndRepo' remains public."
            }
        }
        "private" {
            Write-Host -ForegroundColor Cyan "INFO: Repository '$OwnerAndRepo' is already private. No action needed."
        }
        "internal" {
            Write-Host -ForegroundColor Cyan "INFO: Repository '$OwnerAndRepo' is an internal repository. No action needed."
        }
        default {
            Write-Warning "Could not determine the visibility of '$OwnerAndRepo'. Status reported: '$($repoInfo.visibility)'"
        }
    }
}
catch {
    Write-Error "An error occurred: $_"
}
