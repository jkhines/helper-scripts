#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Extract text from PowerPoint presentations (.pptx files).

.DESCRIPTION
    This PowerShell wrapper calls the Python script to extract text from PowerPoint files.
    Extracts slide titles, content text, alt-text from images, and speaker notes.

.PARAMETER InputFile
    Path to the PowerPoint (.pptx) file to process.

.PARAMETER OutputFile
    Optional path to save the extracted text. If not specified, text is displayed in console.

.EXAMPLE
    .\Extract-PowerPointText.ps1 "presentation.pptx"

.EXAMPLE
    .\Extract-PowerPointText.ps1 "presentation.pptx" "output.txt"

.NOTES
    Requires python-pptx library: pip install python-pptx
#>

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$InputFile,
    
    [Parameter(Mandatory=$false, Position=1)]
    [string]$OutputFile
)

# Get the directory where this script is located
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$PythonScript = Join-Path $ScriptDir "Extract-PowerPointText.py"

# Check if Python script exists
if (-not (Test-Path $PythonScript)) {
    Write-Error "Python script not found: $PythonScript"
    exit 1
}

# Check if input file exists
if (-not (Test-Path $InputFile)) {
    Write-Error "Input file not found: $InputFile"
    exit 1
}

# Validate input file extension
if (-not $InputFile.ToLower().EndsWith('.pptx')) {
    Write-Error "Input file must be a .pptx file"
    exit 1
}

# Build the python command
$PythonArgs = @($PythonScript, $InputFile)
if ($OutputFile) {
    $PythonArgs += $OutputFile
}

# Execute the Python script
try {
    & python @PythonArgs
    $ExitCode = $LASTEXITCODE
    if ($ExitCode -ne 0) {
        exit $ExitCode
    }
} catch {
    Write-Error "Failed to execute Python script: $($_.Exception.Message)"
    exit 1
}