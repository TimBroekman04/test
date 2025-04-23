<#
.SYNOPSIS
    Installs Windows language packs and features on demand robustly for AIB.
.DESCRIPTION
    - Handles servicing tasks
    - Waits for OS readiness
    - Retries on transient errors (including 0x80070020)
    - Disables cleanup tasks
    - Logs all actions
.PARAMETER LanguageList
    Array or string of language names (e.g. "Dutch (Netherlands)")
#>
param(
    [Parameter(Mandatory)]
    [string[]]$LanguageList
)

function Write-Log { param($msg, $lvl = "INFO") ; Write-Host "[$((Get-Date).ToString('s'))][$lvl] $msg" }

# Helper: Wait for servicing tasks to be ready
function Wait-ForServicingReady {
    $tasks = @(
        "\Microsoft\Windows\LanguageComponentsInstaller\Installation",
        "\Microsoft\Windows\LanguageComponentsInstaller\ReconcileLanguageResources"
    )
    foreach ($task in $tasks) {
        $taskObj = Get-ScheduledTask -TaskPath (Split-Path $task -Parent) -TaskName (Split-Path $task -Leaf) -ErrorAction SilentlyContinue
        $attempts = 0
        while ($taskObj.State -ne "Ready" -and $attempts -lt 10) {
            Write-Log "$task not ready, waiting..."
            Start-Sleep -Seconds 5
            $taskObj = Get-ScheduledTask -TaskPath (Split-Path $task -Parent) -TaskName (Split-Path $task -Leaf) -ErrorAction SilentlyContinue
            $attempts++
        }
        if ($taskObj.State -ne "Ready") {
            Write-Log "$task did not reach Ready state after waiting." "ERROR"
        }
    }
}

# Helper: Wait for Windows servicing processes to finish
function Wait-ForServicingProcesses {
    $servicingProcesses = "TiWorker","TrustedInstaller","MoUsoCoreWorker"
    foreach ($proc in $servicingProcesses) {
        while (Get-Process -Name $proc -ErrorAction SilentlyContinue) {
            Write-Log "$proc is running; waiting before language pack installation..."
            Start-Sleep -Seconds 10
        }
    }
}

# Helper: Check for pending reboot
function Test-PendingReboot {
    $reboot = $false
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") { $reboot = $true }
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") { $reboot = $true }
    return $reboot
}

# Step 1: Disable cleanup tasks (per MSFT best practice)
Write-Log "Disabling language pack cleanup tasks."
Disable-ScheduledTask -TaskPath "\Microsoft\Windows\AppxDeploymentClient\" -TaskName "Pre-staged app cleanup" -ErrorAction SilentlyContinue
Disable-ScheduledTask -TaskPath "\Microsoft\Windows\MUI\" -TaskName "LPRemove" -ErrorAction SilentlyContinue
Disable-ScheduledTask -TaskPath "\Microsoft\Windows\LanguageComponentsInstaller" -TaskName "Uninstallation" -ErrorAction SilentlyContinue
reg add "HKLM\SOFTWARE\Policies\Microsoft\Control Panel\International" /v "BlockCleanupOfUnusedPreinstalledLangPacks" /t REG_DWORD /d 1 /f

# Step 2: Enable and start servicing tasks
Write-Log "Enabling and starting language servicing tasks."
$tasks = @(
    "\Microsoft\Windows\LanguageComponentsInstaller\Installation",
    "\Microsoft\Windows\LanguageComponentsInstaller\ReconcileLanguageResources"
)
foreach ($task in $tasks) {
    $t = Get-ScheduledTask -TaskPath (Split-Path $task -Parent) -TaskName (Split-Path $task -Leaf) -ErrorAction SilentlyContinue
    if ($t -and $t.State -ne "Ready") {
        Enable-ScheduledTask -TaskPath (Split-Path $task -Parent) -TaskName (Split-Path $task -Leaf) -ErrorAction SilentlyContinue
        Start-ScheduledTask -TaskPath (Split-Path $task -Parent) -TaskName (Split-Path $task -Leaf) -ErrorAction SilentlyContinue
    }
}

Wait-ForServicingReady

# Step 3: Check for pending reboot
if (Test-PendingReboot) {
    Write-Log "Pending reboot detected. Restarting system."
    Restart-Computer -Force
    Start-Sleep -Seconds 60
    exit 3010
}

# Step 4: Wait for servicing processes to finish
Wait-ForServicingProcesses

# Step 5: Install language packs with retry logic
$maxAttempts = 3
foreach ($language in $LanguageList) {
    $success = $false
    for ($attempt=1; $attempt -le $maxAttempts; $attempt++) {
        try {
            Write-Log "*** Installing language pack [$language] (Attempt $attempt/$maxAttempts) ***"
            # Replace this with your actual install logic, e.g.:
            Install-Language -Language $language -CopyToSettings -ExcludeFeatures
            # Check for success, throw on partial install
            # (If using MSFT module, check $LASTEXITCODE or returned object)
            $success = $true
            Write-Log "Language pack [$language] installed successfully."
            break
        } catch {
            Write-Log "Attempt $attempt failed: $_" "WARNING"
            Start-Sleep -Seconds (10 * $attempt)
            if ($attempt -eq $maxAttempts) {
                Write-Log "Language pack [$language] failed after $maxAttempts attempts." "ERROR"
                throw
            }
        }
    }
}

Write-Log "All language packs processed."
exit 0
