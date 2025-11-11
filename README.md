# Helper Scripts

A collection of PowerShell and Python utility scripts for common administrative and development tasks.

## Overview

This repository contains helper scripts organized by category:
- **Active Directory**: User and group management scripts
- **AWS**: AWS credential management and ECR operations
- **GitHub**: Repository management and PR metrics analysis
- **Office**: PowerPoint file processing utilities

## Prerequisites

### PowerShell Scripts
- PowerShell 5.1 or later
- Required modules:
  - `ActiveDirectory` (for AD scripts - install RSAT tools)
  - AWS CLI v2 (for AWS scripts)

### Python Scripts
- Python 3.8 or later
- **For GitHub PR Metrics**: `uv` package manager (recommended) - [Install uv](https://github.com/astral-sh/uv)
- **For other Python scripts**: Required packages (install via `pip`):
  - `python-pptx` (for PowerPoint extraction)
  - `pillow` and `pdf2image` (for PowerPoint conversion)
  - `poppler` (system dependency for PDF processing)

## Setup

### 1. Clone the Repository

```powershell
git clone https://github.com/jkhines/helper-scripts.git
cd helper-scripts
```

### 2. Configure AWS Settings

Copy the example AWS configuration file and update it with your settings:

```powershell
Copy-Item aws-config.json.example aws-config.json
```

Edit `aws-config.json` and update:
- `sso_start_url`: Your AWS SSO start URL
- `accounts`: Your AWS account IDs for dev, staging, and prod environments

**Note**: `aws-config.json` is excluded from git to protect sensitive information.

### 3. Configure GitHub Settings

Copy the example GitHub configuration file and update it with your repository names:

```powershell
Copy-Item github-config.json.example github-config.json
```

Edit `github-config.json` and update:
- `repos`: List of repositories to analyze (format: `owner/repo-name`)
- `start_date` and `end_date`: Default date ranges (optional, can be overridden via command-line)

**Note**: `github-config.json` is excluded from git to protect sensitive information.

### 4. Set Up GitHub PR Metrics (using uv)

Navigate to the `github` directory and install dependencies using `uv`:

```powershell
cd github
uv sync
```

This will create a virtual environment and install the required dependencies (`requests`).

### 5. Set Environment Variables

For GitHub scripts, set your GitHub token:

```powershell
$env:GITHUB_TOKEN = "your-github-token-here"
```

Or set it permanently in your system environment variables.

## Scripts

### Active Directory Scripts

Located in `active-directory/`. These scripts require Active Directory module and VPN access.

#### `searchad.ps1`
Core search function for Active Directory objects (users, groups, computers, WWIDs).

**Usage:**
```powershell
.\active-directory\searchad.ps1 -User "username"
.\active-directory\searchad.ps1 -WWID 12345678
.\active-directory\searchad.ps1 -Group "groupname"
.\active-directory\searchad.ps1 -Computer "computername"
```

#### `finduser.ps1`
Find user information including organizational unit groups.

**Usage:**
```powershell
.\active-directory\finduser.ps1 -UsernameOrWWID "username"
.\active-directory\finduser.ps1 -UsernameOrWWID "12345678"
```

#### `groups.ps1`
List all groups a user belongs to.

**Usage:**
```powershell
.\active-directory\groups.ps1 -Username "username"
```

#### `manager.ps1`
Get a user's manager information.

**Usage:**
```powershell
.\active-directory\manager.ps1 -Username "username"
```

#### `members.ps1`
List all members of a group.

**Usage:**
```powershell
.\active-directory\members.ps1 -Groupname "groupname"
```

#### `reports.ps1`
List direct reports for a user.

**Usage:**
```powershell
.\active-directory\reports.ps1 -Username "username"
```

#### `passexp.ps1`
Check password expiration dates for users.

**Usage:**
```powershell
.\active-directory\passexp.ps1 -UsernameOrWWID "username"
```

#### `lastname.ps1`
Search for users by last name.

**Usage:**
```powershell
.\active-directory\lastname.ps1 -Surname "Smith"
```

#### `phone.ps1`
Get user phone and employee ID information.

**Usage:**
```powershell
.\active-directory\phone.ps1 -UsernameOrWWID "username"
```

#### `wwid.ps1`
Get WWID (employee ID) for a user.

**Usage:**
```powershell
.\active-directory\wwid.ps1 -Username "username"
```

### AWS Scripts

Located in `aws/`. These scripts require AWS CLI v2 and proper configuration.

#### `Get-AWSCreds.ps1`
Fetch short-term AWS credentials via AWS IAM Identity Center (SSO) and export them as environment variables.

**Usage:**
```powershell
.\aws\Get-AWSCreds.ps1 -Account dev
.\aws\Get-AWSCreds.ps1 -Account staging
.\aws\Get-AWSCreds.ps1 -Account prod
```

**Requirements:**
- AWS CLI v2 installed
- `aws-config.json` configured with your account IDs and SSO URL
- SSO profile configured (will be auto-created if missing)

#### `Move-LatestTag.ps1`
Move the `latest` tag in an ECR repository to point to a specific image digest or tag.

**Usage:**
```powershell
.\aws\Move-LatestTag.ps1 -DestinationImageUri "123456789012.dkr.ecr.us-west-2.amazonaws.com/repo:tag"
.\aws\Move-LatestTag.ps1 -DestinationImageUri "123456789012.dkr.ecr.us-west-2.amazonaws.com/repo@sha256:abc123..."
```

### GitHub Scripts

Located in `github/`. These scripts require GitHub CLI or GitHub API token.

#### `fetch_pr_metrics.py`
Analyze PR metrics for specified repositories within a date range.

**Setup:**
```powershell
cd github
uv sync
```

**Usage:**
```powershell
# Use defaults (2 weeks ago to now)
uv run fetch_pr_metrics.py

# Specify custom date range
uv run fetch_pr_metrics.py --start-date "2025-01-01T00:00:00Z" --end-date "2025-01-31T23:59:59Z"

# Specify only start date (end defaults to now)
uv run fetch_pr_metrics.py --start-date "2025-01-01T00:00:00Z"
```

**Alternative (without uv):**
If you prefer to use Python directly, ensure `requests` is installed:
```powershell
pip install requests
python .\github\fetch_pr_metrics.py --start-date "2025-01-01T00:00:00Z"
```

**Requirements:**
- `github-config.json` configured with repository names
- `GITHUB_TOKEN` environment variable set
- `uv` installed (recommended) or `requests` package via pip

**Output:**
- Generates `pr_metrics_report.md` and `pr_metrics_report.txt` with detailed PR analysis

#### `Convert-PublicRepo.ps1`
Convert a public GitHub repository to private.

**Usage:**
```powershell
.\github\Convert-PublicRepo.ps1 -OwnerAndRepo "owner/repo-name"
.\github\Convert-PublicRepo.ps1 -OwnerAndRepo "https://github.com/owner/repo.git" -Force
```

**Requirements:**
- GitHub CLI (`gh`) installed and authenticated
- Admin permissions on the target repository

#### `Rename-GitHubRepository.ps1`
Rename a GitHub repository.

**Usage:**
```powershell
.\github\Rename-GitHubRepository.ps1 -FullName "owner/old-name" -NewName "new-name"
.\github\Rename-GitHubRepository.ps1 -FullName "owner/old-name" -NewName "new-name" -Force
```

**Requirements:**
- GitHub CLI (`gh`) installed and authenticated
- Admin permissions on the target repository

### Office Scripts

Located in `office/`. These scripts process PowerPoint presentations.

#### `Extract-PowerPointText.py` / `Extract-PowerPointText.ps1`
Extract text content from PowerPoint presentations including titles, content, alt-text, and speaker notes.

**Usage:**
```powershell
.\office\Extract-PowerPointText.ps1 "presentation.pptx"
.\office\Extract-PowerPointText.ps1 "presentation.pptx" "output.txt"

# Or directly with Python
python .\office\Extract-PowerPointText.py "presentation.pptx" "output.txt"
```

**Requirements:**
- Python package: `python-pptx`

#### `Convert-PptxToPng.py`
Convert PowerPoint presentations to PNG mosaic images (all slides in a grid).

**Usage:**
```powershell
# Convert a specific file
python .\office\Convert-PptxToPng.py "presentation.pptx"

# Convert all PPTX files in current directory
python .\office\Convert-PptxToPng.py --all

# Custom thumbnail size
python .\office\Convert-PptxToPng.py "presentation.pptx" --width 1920 --height 1080
```

**Requirements:**
- LibreOffice installed (`soffice` executable)
- Poppler installed (`pdftoppm` executable)
- Python packages: `pillow`, `pdf2image`

## Security Notes

- Configuration files containing sensitive information (`aws-config.json`, `github-config.json`) are excluded from git via `.gitignore`
- Always use example files (`*.example`) as templates
- Never commit actual credentials, tokens, or account IDs to the repository
- GitHub tokens should be stored as environment variables, not in files

## Contributing

When adding new scripts:
1. Place them in the appropriate directory based on their function
2. Include proper parameter documentation
3. Add usage examples in script comments
4. Update this README with script descriptions
5. Ensure any sensitive configuration uses example files

## License

This repository is licensed under the MIT License. See [LICENSE](LICENSE) for details.

