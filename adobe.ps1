<#
.SYNOPSIS
    Installs a package via WinGet in SYSTEM context (Packer/AIB), with full bootstrapping.
.DESCRIPTION
    - Ensures all WinGet prerequisites are present.
    - Repairs/bootstraps WinGet using PowerShell module if needed.
    - Installs the specified package.
    - Designed for non-interactive image builds (Packer, AIB).
#>

$ErrorActionPreference = 'Stop'
$LogPath = "$env:SystemDrive\buildArtifacts\WinGetInstall.log"
$PackageId = 'Adobe.Acrobat.Reader.64-bit' 

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

Write-Log "Starting WinGet install script for SYSTEM context."

# Step 1: Ensure prerequisites (VC++ runtimes, UWP dependencies, DesktopAppInstaller)
# See: https://github.com/microsoft/winget-cli#dependencies
function Ensure-WinGetPrereqs {
    Write-Log "Ensuring WinGet prerequisites are installed..."

    # Install VC++ Redistributables (required for WinGet)
    $vcRedistUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
    $vcRedistPath = "$env:TEMP\vc_redist.x64.exe"
    Invoke-WebRequest -Uri $vcRedistUrl -OutFile $vcRedistPath -UseBasicParsing
    Start-Process -FilePath $vcRedistPath -ArgumentList "/install /quiet /norestart" -Wait

    # Install Desktop App Installer (winget host)
    $wingetMsixUrl = "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    $wingetMsixPath = "$env:TEMP\DesktopAppInstaller.msixbundle"
    Invoke-WebRequest -Uri $wingetMsixUrl -OutFile $wingetMsixPath -UseBasicParsing
    Add-AppxProvisionedPackage -Online -PackagePath $wingetMsixPath -SkipLicense

    Write-Log "Prerequisites installed."
}

# Step 2: Repair/Bootstrap WinGet using PowerShell module
function Repair-WinGet {
    Write-Log "Repairing/bootstrapping WinGet with PowerShell module..."
    Install-Module -Name Microsoft.WinGet.Client -Force -AllowClobber -Scope AllUsers
    Import-Module Microsoft.WinGet.Client
    Repair-WinGetPackageManager -Force
    Write-Log "WinGet repair/bootstrap complete."
}

# Step 3: Install the package
function Install-WithWinGet {
    Write-Log "Attempting to install package: $PackageId"
    try {
        $result = winget install --id $PackageId --silent --accept-package-agreements --accept-source-agreements --scope machine --disable-interactivity 2>&1
        Write-Log $result
        if ($LASTEXITCODE -eq 0) {
            Write-Log "WinGet package installed successfully."
        } else {
            Write-Log "ERROR: WinGet install exited with code $LASTEXITCODE"
            exit $LASTEXITCODE
        }
    } catch {
        Write-Log "ERROR: WinGet install failed. $_"
        exit 1
    }
}

# Main logic
try {
    Ensure-WinGetPrereqs
    Repair-WinGet
    Install-WithWinGet
} catch {
    Write-Log "Fatal script error: $_"
    exit 1
}

Write-Log "WinGet install script completed."
exit 0
