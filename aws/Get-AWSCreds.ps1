<#
.SYNOPSIS
Fetch short-term AWS credentials via AWS IAM Identity Center (SSO) and export them as environment variables.

.DESCRIPTION
Automates the browser-based SSO login (PingOne) using AWS CLI v2. After a successful login it:
1. Lists SSO accounts.
2. Lets you choose one of the predefined accounts (sb, dev, prod, omdev, omstaging, omprod).
3. Lets you select a role (if multiple are available).
4. Retrieves role credentials.
5. Sets AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN for the current PowerShell session.

Run the script in a PowerShell window that already has AWS CLI v2 installed and configured with a basic SSO profile (see REQUIREMENTS).

.REQUIREMENTS
- AWS CLI v2 (https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- Configuration file: Copy aws-config.json.example to aws-config.json in the same directory as this script and update with your AWS account IDs and SSO settings.
- A profile named "sso" configured via `aws configure sso --profile sso` (will be auto-created if missing using values from config file).
#>

[CmdletBinding()]
param(
    [ValidateSet('sb','dev','prod','omdev','omstaging','omprod')]
    [string]$Account,

    [string]$Profile = 'sso',
    
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'aws-config.json')
)

# Load configuration from JSON file
if (-not (Test-Path $ConfigPath)) {
    throw "Configuration file not found: $ConfigPath. Please copy aws-config.json.example to aws-config.json and update with your settings."
}
$configFile = Resolve-Path $ConfigPath
$config = Get-Content $configFile -Raw | ConvertFrom-Json

# Map friendly names to account IDs from config
$AccountMap = @{
    sb        = $config.accounts.sb
    dev       = $config.accounts.dev
    prod      = $config.accounts.prod
    omdev     = $config.accounts.omdev
    omstaging = $config.accounts.omstaging
    omprod    = $config.accounts.omprod
}

function Test-AwsCli {
    if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
        throw 'AWS CLI v2 is required but was not found in PATH.'
    }
    $versionString = (& aws --version) 2>&1
    if (-not $versionString.StartsWith('aws-cli/2')) {
        throw "AWS CLI v2 is required. Detected: $versionString"
    }
}

function Ensure-SsoProfile {
    param([string]$ProfileName)

    # Retrieve configured profiles from AWS CLI
    $profiles = (& aws configure list-profiles) -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    if ($profiles -notcontains $ProfileName) {
        Write-Host "Profile '$ProfileName' not found. Creating it now ..." -ForegroundColor Yellow

        aws configure set sso_start_url $config.sso_start_url --profile $ProfileName | Out-Null
        aws configure set sso_region    $config.sso_region     --profile $ProfileName | Out-Null
        aws configure set region       $config.region        --profile $ProfileName | Out-Null

        Write-Host "Profile '$ProfileName' created." -ForegroundColor Green
    }
}

function Invoke-SsoLogin {
    Ensure-SsoProfile -ProfileName $Profile
    Write-Verbose "Running 'aws sso login --profile $Profile' ..."
    aws sso login --profile $Profile | Out-Null
    $env:AWS_PROFILE = $Profile
}

function Get-AccessToken {
    $cacheDir = Join-Path $env:USERPROFILE '.aws\sso\cache'
    if (-not (Test-Path $cacheDir)) { throw 'SSO cache directory not found.' }

    $latest = Get-ChildItem $cacheDir -Filter '*.json' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latest) { throw 'No cached SSO token file found.' }

    $data = Get-Content $latest.FullName | ConvertFrom-Json

    # Optional: check expiry
    $expiry = [DateTime]::Parse($data.expiresAt)
    if ($expiry -lt (Get-Date).ToUniversalTime().AddMinutes(-5)) {
        throw 'Cached SSO token is expired. Run aws sso login again.'
    }

    return $data.accessToken
}

function Choose-Role {
    param(
        [string]$AccountId,
        [string]$AccessToken
    )

    $roles = (
        aws sso list-account-roles --account-id $AccountId --access-token $AccessToken --output json |
        ConvertFrom-Json
    ).roleList

    if ($null -eq $roles -or $roles.Count -eq 0) {
        throw "No roles found for account $AccountId."
    }
    if ($roles.Count -eq 1) {
        return $roles[0].roleName
    }

    Write-Host 'Available roles:' -ForegroundColor Cyan
    for ($i = 0; $i -lt $roles.Count; $i++) {
        Write-Host "[$($i+1)] $($roles[$i].roleName)"
    }

    do {
        $sel = Read-Host 'Select role number'
    } while (-not ($sel -as [int]) -or $sel -lt 1 -or $sel -gt $roles.Count)

    $roles[$sel - 1].roleName
}

try {
    Test-AwsCli

    if (-not $Account) {
        $Account = Read-Host 'Enter account name (sb, dev, prod, omdev, omstaging, omprod)'
    }
    $AccountId = $AccountMap[$Account]
    if (-not $AccountId) {
        throw "Unknown account '$Account'."
    }

    Invoke-SsoLogin
    $token = Get-AccessToken

    $role  = Choose-Role -AccountId $AccountId -AccessToken $token

    $creds = (
        aws sso get-role-credentials --account-id $AccountId --role-name $role --access-token $token --output json |
        ConvertFrom-Json
    ).roleCredentials

    # Export credentials to current session
    $env:AWS_ACCESS_KEY_ID     = $creds.accessKeyId
    $env:AWS_SECRET_ACCESS_KEY = $creds.secretAccessKey
    $env:AWS_SESSION_TOKEN     = $creds.sessionToken

    $expiry = [DateTimeOffset]::FromUnixTimeMilliseconds($creds.expiration).ToLocalTime()
    Write-Host "`nCredentials set for account $Account ($AccountId), role $role. Expires $expiry." -ForegroundColor Green
}
catch {
    Write-Error $_.Exception.Message
} 