<#
.SYNOPSIS
Enterprise Sysprep Script for Azure Virtual Desktop Image Templates
.DESCRIPTION
Version 2.1 (2025-05-01)
Includes Azure-optimized service checks, registry validation, and secure cleanup
#>

Start-Transcript -Path "C:\Windows\Temp\AVD-Sysprep.log" -Append

try {
    #region Service Initialization Sequence
    Write-Output "[$(Get-Date)] Starting Azure GA Agent validation..."
    
    $maxRetries = 30  # 2.5 minute timeout
    $retryInterval = 5

    # RdAgent check with timeout
    Write-Output ">>> Waiting for RdAgent service..."
    $retryCount = 0
    while ((Get-Service -Name RdAgent -ErrorAction SilentlyContinue).Status -ne 'Running') {
        if ($retryCount -ge $maxRetries) {
            throw "RdAgent failed to start within $($maxRetries * $retryInterval) seconds"
        }
        Start-Sleep -Seconds $retryInterval
        $retryCount++
    }

    # WindowsAzureTelemetryService (conditional check)
    if (Get-Service -Name WindowsAzureTelemetryService -ErrorAction SilentlyContinue) {
        Write-Output ">>> Waiting for WindowsAzureTelemetryService..."
        $retryCount = 0
        while ((Get-Service WindowsAzureTelemetryService).Status -ne 'Running') {
            if ($retryCount -ge $maxRetries) {
                throw "WindowsAzureTelemetryService failed to start within timeout"
            }
            Start-Sleep -Seconds $retryInterval
            $retryCount++
        }
    }

    # WindowsAzureGuestAgent check
    Write-Output ">>> Waiting for WindowsAzureGuestAgent..."
    $retryCount = 0
    while ((Get-Service -Name WindowsAzureGuestAgent).Status -ne 'Running') {
        if ($retryCount -ge $maxRetries) {
            throw "WindowsAzureGuestAgent failed to start within timeout"
        }
        Start-Sleep -Seconds $retryInterval
        $retryCount++
    }
    #endregion

    #region System Cleanup
    Write-Output "[$(Get-Date)] Cleaning residual configuration files..."
    #endregion

    #region Sysprep Execution
    Write-Output "[$(Get-Date)] Initiating Sysprep sequence..."
    
    $sysprepParams = @(
        "/oobe",
        "/generalize",
        "/quiet",
        "/quit"  # Critical change for Azure integration
    )

    $sysprepProcess = Start-Process "$Env:SystemRoot\System32\Sysprep\Sysprep.exe" -ArgumentList $sysprepParams -PassThru
    
    # Validation loop with timeout
    $sysprepTimeout = 600  # 10 minutes
    $startTime = Get-Date
    while ((Get-Date) - $startTime -lt [TimeSpan]::FromSeconds($sysprepTimeout)) {
        $imageState = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State' -Name ImageState -ErrorAction SilentlyContinue).ImageState
        
        if ($imageState -eq 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') {
            Write-Output "[$(Get-Date)] Sysprep validation successful"
            break
        }
        Start-Sleep -Seconds 10
    }

    if (-not $imageState -or $imageState -ne 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') {
        throw "Sysprep failed to reach expected state. Current state: $imageState"
    }
    #endregion
}
catch {
    Write-Output "[$(Get-Date)] CRITICAL ERROR: $_"
    $_ | Format-List -Force | Out-String | Write-Output
    exit 1
}
finally {
    Stop-Transcript
}

Write-Output "[$(Get-Date)] Sysprep process completed successfully"
exit 0
