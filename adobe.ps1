<#
.SYNOPSIS
    Installs Adobe Acrobat Reader DC (64-bit) using winget if not already present, using only winget list Adobe* for detection.
.DESCRIPTION
    - Uses 'winget list Adobe*' to check for installed Adobe Acrobat Reader (32/64-bit).
    - Installs Adobe Acrobat Reader DC (64-bit) if not found.
    - Logs all actions and errors.
#>

$ErrorActionPreference = 'Stop'
$LogPath = "$env:SystemDrive\buildArtifacts\AdobeReaderInstall.log"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timestamp $Message"
    Write-Output $entry
    Add-Content -Path $LogPath -Value $entry
}

# Ensure log directory exists
if (-not (Test-Path -Path (Split-Path $LogPath))) {
    New-Item -Path (Split-Path $LogPath) -ItemType Directory -Force | Out-Null
}

Write-Log "Starting Adobe Reader install script (winget version, detection via winget list Adobe*)."

# Find winget.exe
function Get-WingetPath {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($winget) { return $winget.Source }
    $wingetPaths = Get-ChildItem "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue | Sort-Object -Property LastWriteTime | Select-Object -Last 1
    if ($wingetPaths) { return $wingetPaths.FullName }
    $userWinget = "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"
    if (Test-Path $userWinget) { return $userWinget }
    return $null
}

$wingetPath = Get-WingetPath
if (-not $wingetPath) {
    Write-Log "ERROR: winget is not installed or not available."
    exit 1
}
Write-Log "winget found at: $wingetPath"

# Use winget list Adobe* to check for installed Reader
Write-Log "Checking for installed Adobe Acrobat Reader via 'winget list Adobe*'..."
$adobeList = & "$wingetPath" list Adobe* 2>&1

# Look for 32-bit or 64-bit Reader in the output
if ($adobeList -match "Adobe Acrobat Reader DC" -or
    $adobeList -match "Adobe.Acrobat.Reader.64-bit" -or
    $adobeList -match "Adobe.Acrobat.Reader.32-bit") {
    Write-Log "Adobe Acrobat Reader is already installed (winget list check). Skipping installation."
    exit 0
}

Write-Log "Adobe Acrobat Reader not found. Installing with winget..."
try {
    $installResult = & "$wingetPath" install --id 'Adobe.Acrobat.Reader.64-bit' --silent --accept-package-agreements --accept-source-agreements --scope machine 2>&1
    Write-Log $installResult
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Adobe Reader installed successfully via winget."
    } else {
        Write-Log "ERROR: winget install exited with code $LASTEXITCODE"
        exit $LASTEXITCODE
    }
} catch {
    Write-Log "ERROR: winget install failed. $_"
    exit 1
}

Write-Log "Adobe Reader installation script completed."
exit 0
