<#
.SYNOPSIS
    Installs Adobe Acrobat Reader DC silently for Azure Image Builder.
.DESCRIPTION
    - Downloads latest Acrobat Reader DC enterprise installer (EN-US, 64-bit).
    - Installs silently.
    - Logs outcome, handles failures.
.NOTES
    Customize $DownloadUrl for other locales/versions.
#>

param (
    [string]$DownloadUrl = "https://ardownload2.adobe.com/pub/adobe/reader/win/AcrobatDC/2400120583/AcroRdrDC2400120583_en_US.exe",
    [string]$LogPath = "C:\Windows\Temp\InstallAdobeAcrobat.log"
)

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMsg = "$timestamp $message"
    Write-Host $logMsg
    Add-Content -Path $LogPath -Value $logMsg
}

try {
    Write-Log "Starting Adobe Acrobat Reader DC install."

    $installerPath = "$env:TEMP\AcroRdrDC_installer.exe"

    # Download installer
    Write-Log "Downloading Adobe Acrobat Reader from $DownloadUrl"
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $installerPath -ErrorAction Stop

    # Install silently
    Write-Log "Running silent installation."
    $arguments = "/sAll /rs /rps /msi EULA_ACCEPT=YES /quiet /norestart"
    $process = Start-Process -FilePath $installerPath -ArgumentList $arguments -Wait -PassThru

    # Check exit code
    if ($process.ExitCode -eq 0) {
        Write-Log "Adobe Acrobat Reader installed successfully."
    } else {
        Write-Log "Installer returned exit code $($process.ExitCode)."
        throw "Adobe Acrobat Reader installation failed with code $($process.ExitCode)."
    }

    # Cleanup installer
    if (Test-Path $installerPath) {
        Remove-Item $installerPath -Force
        Write-Log "Cleaned up installer."
    }
} catch {
    Write-Log "Error: $_"
    throw
}
