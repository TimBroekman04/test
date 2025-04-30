Write-Output '>>> Waiting for GA Service (RdAgent) to start ...'
while ((Get-Service RdAgent).Status -ne 'Running') { Start-Sleep -Seconds 5 }

Write-Output '>>> Waiting for GA Service (WindowsAzureGuestAgent) to start ...'
while ((Get-Service WindowsAzureGuestAgent).Status -ne 'Running') { Start-Sleep -Seconds 5 }

# Only check for WindowsAzureTelemetryService if it exists
if (Get-Service -Name 'WindowsAzureTelemetryService' -ErrorAction SilentlyContinue) {
    Write-Output '>>> Waiting for GA Service (WindowsAzureTelemetryService) to start ...'
    while ((Get-Service WindowsAzureTelemetryService).Status -ne 'Running') { Start-Sleep -Seconds 5 }
}

# Clean up unattend files
if (Test-Path "$Env:SystemRoot\system32\Sysprep\unattend.xml") {
    Write-Output '>>> Removing Sysprep\unattend.xml ...'
    Remove-Item "$Env:SystemRoot\system32\Sysprep\unattend.xml" -Force
}
if (Test-Path "$Env:SystemRoot\Panther\unattend.xml") {
    Write-Output '>>> Removing Panther\unattend.xml ...'
    Remove-Item "$Env:SystemRoot\Panther\unattend.xml" -Force
}

Write-Output '>>> Sysprepping VM ...'
& "$Env:SystemRoot\System32\Sysprep\Sysprep.exe" /oobe /generalize /quiet /quit

# Wait for Sysprep to finish
while ($true) {
    $imageState = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State').ImageState
    Write-Output $imageState
    if ($imageState -eq 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') { break }
    Start-Sleep -Seconds 5
}

Write-Output '>>> Sysprep complete ...'
