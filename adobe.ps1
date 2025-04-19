# Check if Adobe Acrobat Reader DC is already installed
$adobeInstalled = Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* |
    Where-Object { $_.DisplayName -like "Adobe Acrobat Reader DC*" }

if (-not $adobeInstalled) {
    $installDir = "C:\Temp\AdobeInstall"
    $installer = "$installDir\AcroRdrDC.exe"
    $adobeUrl = "ftp://ftp.adobe.com/pub/adobe/reader/win/AcrobatDC/2300120143/AcroRdrDC2300120143_en_US.exe" # Update version as needed

    try {
        # Create temp directory
        if (-not (Test-Path $installDir)) {
            New-Item -Path $installDir -ItemType Directory -Force | Out-Null
        }

        # Download the installer
        Write-Host "Downloading Adobe Reader installer..."
        Invoke-WebRequest -Uri $adobeUrl -OutFile $installer

        # Install silently
        Write-Host "Installing Adobe Reader silently..."
        Start-Process -FilePath $installer -ArgumentList "/sAll /rs /rps /msi /norestart /quiet EULA_ACCEPT=YES" -Wait

        # Cleanup
        Remove-Item -Path $installer -Force
        Remove-Item -Path $installDir -Force

        Write-Host "Adobe Reader installation completed successfully."
    } catch {
        Write-Error "Adobe Reader installation failed: $_"
        exit 1
    }
} else {
    Write-Host "Adobe Acrobat Reader DC is already installed. Skipping installation."
    exit 0
}
