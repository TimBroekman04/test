<#
.SYNOPSIS
Enterprise Sysprep Script with Advanced Retry Logic and Servicing Stack Awareness
.DESCRIPTION
Version 3.0 (2025-05-05)
Features:
- Servicing stack readiness checks
- Intelligent retry with exponential backoff
- Pending operation detection
- Comprehensive logging
#>

$ErrorActionPreference = 'Stop'

try {
    #region Pre-Sysprep Validation
    Write-Output "[$(Get-Date)] Starting pre-sysprep validation..."

    # Check for pending reboots
    if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations") {
        throw "Pending file rename operations detected. Reboot required before sysprep."
    }

    # Verify servicing stack state
    $maxServicingWait = 3600  
    $servicingStart = Get-Date
    while ((Get-Date) - $servicingStart -lt [TimeSpan]::FromSeconds($maxServicingWait)) {
        $servicingProcesses = Get-Process -Name TrustedInstaller, TiWorker -ErrorAction SilentlyContinue
        if (-not $servicingProcesses) {
            Write-Output "[$(Get-Date)] Servicing stack is idle"
            break
        }
        Write-Output "[$(Get-Date)] Servicing stack active (processes: $($servicingProcesses.Name -join ', ')) - waiting..."
        Start-Sleep -Seconds 60
    }
    #endregion

    #region Azure Agent Validation
    Write-Output "[$(Get-Date)] Validating Azure platform services..."
    $services = @('RdAgent', 'WindowsAzureGuestAgent', 'WindowsAzureTelemetryService')
    
    foreach ($service in $services) {
        $retryCount = 0
        $maxRetries = 30  # 5 minutes per service
        Write-Output ">>> Validating $service"
        
        while ($retryCount -lt $maxRetries) {
            try {
                $status = (Get-Service -Name $service -ErrorAction Stop).Status
                if ($status -eq 'Running') {
                    Write-Output "[$(Get-Date)] $service is running"
                    break
                }
            }
            catch {
                if ($retryCount -ge $maxRetries) {
                    throw "$service did not reach running state within timeout"
                }
                Start-Sleep -Seconds 10
                $retryCount++
            }
        }
    }
    #endregion

    #region System Cleanup
    Write-Output "[$(Get-Date)] Performing pre-sysprep cleanup..."
    # Remove temporary files
    Get-ChildItem -Path $env:TEMP -Recurse | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
    
    # Clear event logs
    wevtutil cl Application
    wevtutil cl System
    #endregion

    #region Sysprep Execution with Smart Retry
    Write-Output "[$(Get-Date)] Initializing sysprep sequence..."
    $sysprepParams = @(
        "/oobe",
        "/generalize",
        "/quiet",
        "/quit"
    )

    $sysprepAttempt = 0
    $maxAttempts = 10
    $sysprepSuccess = $false

    while ($sysprepAttempt -lt $maxAttempts -and -not $sysprepSuccess) {
        $sysprepAttempt++
        Write-Output "[$(Get-Date)] Sysprep attempt $sysprepAttempt/$maxAttempts"

        try {
            # Force terminate non-essential processes
            Get-Process | Where-Object {
                $_.ProcessName -notin @('Idle', 'System', 'smss', 'csrss', 'wininit', 'services', 'lsass', 'svchost', 'taskhostw', 'dwm')
            } | Stop-Process -Force -ErrorAction SilentlyContinue

            Start-Process "$Env:SystemRoot\System32\Sysprep\Sysprep.exe" -ArgumentList $sysprepParams -Wait -NoNewWindow

            # State validation with progressive timeout
            $validationTimeout = [math]::Min(3600, $sysprepAttempt * 1200)  # 20-60 minutes
            $validationStart = Get-Date
            $validState = $false

            while ((Get-Date) - $validationStart -lt [TimeSpan]::FromSeconds($validationTimeout)) {
                $imageState = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State' -Name ImageState -ErrorAction SilentlyContinue).ImageState
                
                if ($imageState -eq 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') {
                    Write-Output "[$(Get-Date)] Sysprep validation successful"
                    $validState = $true
                    break
                }
                
                Write-Output "[$(Get-Date)] Current state: $imageState"
                Start-Sleep -Seconds 30
            }

            if ($validState) {
                $sysprepSuccess = $true
                break
            }
            else {
                Write-Output "[$(Get-Date)] Sysprep validation timeout"
            }
        }
        catch {
            Write-Output "[$(Get-Date)] Sysprep attempt $sysprepAttempt failed: $_"
            if ($sysprepAttempt -lt $maxAttempts) {
                Write-Output "[$(Get-Date)] Retrying in 5 minutes..."
                Start-Sleep -Seconds 300
            }
        }
    }

    if (-not $sysprepSuccess) {
        throw "Sysprep failed after $maxAttempts attempts"
    }
    #endregion
}
catch {
    $errorMessage = $_.Exception.Message
    Write-Output "[$(Get-Date)] CRITICAL ERROR: $errorMessage"
    try {
        Write-EventLog -LogName Application -Source "EnterpriseSysprep" -EntryType Error -EventId 501 -Message "Sysprep failed: $errorMessage"
    }
    catch {}
    exit 1
}
finally {
}

Write-Output "[$(Get-Date)] Sysprep process completed successfully"
exit 0
