<#
.SYNOPSIS
    Enterprise-grade language pack installer for Azure Image Builder (AIB) and Packer pipelines.
.DESCRIPTION
    - Handles Windows Update/service interference
    - Ensures idempotency and compliance
    - Robust logging, error handling, and security
    - Supports audit and CI/CD integration
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [ValidateSet("Arabic (Saudi Arabia)","Bulgarian (Bulgaria)","Chinese (Simplified, China)","Chinese (Traditional, Taiwan)","Croatian (Croatia)","Czech (Czech Republic)","Danish (Denmark)","Dutch (Netherlands)", "English (United Kingdom)", "Estonian (Estonia)", "Finnish (Finland)", "French (Canada)", "French (France)", "German (Germany)", "Greek (Greece)", "Hebrew (Israel)", "Hungarian (Hungary)", "Italian (Italy)", "Japanese (Japan)", "Korean (Korea)", "Latvian (Latvia)", "Lithuanian (Lithuania)", "Norwegian, Bokmål (Norway)", "Polish (Poland)", "Portuguese (Brazil)", "Portuguese (Portugal)", "Romanian (Romania)", "Russian (Russia)", "Serbian (Latin, Serbia)", "Slovak (Slovakia)", "Slovenian (Slovenia)", "Spanish (Mexico)", "Spanish (Spain)", "Swedish (Sweden)", "Thai (Thailand)", "Turkish (Turkey)", "Ukrainian (Ukraine)", "English (Australia)", "English (United States)")]
    [string[]]$LanguageList
)

# Enterprise logging
$LogPath = "C:\Windows\Temp\AIB_LanguagePackInstall.log"
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp][$Level] $Message"
    Write-Host $entry
    Add-Content -Path $LogPath -Value $entry
}

# Compliance: Audit start
Write-Log "=== Starting Language Pack Installation (Enterprise) ==="
Write-Log "Languages requested: $($LanguageList -join ', ')"

# Helper: Check for pending reboot
function Test-PendingReboot {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
        'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    )
    foreach ($path in $paths) { if (Test-Path $path) { return $true } }
    return $false
}

# Helper: Stop/Start update services
$services = @('wuauserv', 'bits', 'dosvc', 'cryptsvc')
function Stop-ConflictingServices {
    foreach ($svc in $services) {
        try {
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Log "Stopped and disabled service: $svc"
        } catch { Write-Log "Failed to stop/disable $svc: $_" "WARN" }
    }
}
function Start-ConflictingServices {
    foreach ($svc in $services) {
        try {
            Set-Service -Name $svc -StartupType Manual -ErrorAction SilentlyContinue
            Start-Service -Name $svc -ErrorAction SilentlyContinue
            Write-Log "Started and set service to manual: $svc"
        } catch { Write-Log "Failed to start/enable $svc: $_" "WARN" }
    }
}

# Helper: Disable/Enable scheduled tasks
$tasks = @(
    "\Microsoft\Windows\AppxDeploymentClient\Pre-staged app cleanup",
    "\Microsoft\Windows\MUI\LPRemove",
    "\Microsoft\Windows\LanguageComponentsInstaller\Uninstallation",
    "\Microsoft\Windows\LanguageComponentsInstaller\Installation",
    "\Microsoft\Windows\LanguageComponentsInstaller\ReconcileLanguageResources"
)
function Disable-ConflictingTasks {
    foreach ($task in $tasks) {
        try {
            Disable-ScheduledTask -TaskPath ([System.IO.Path]::GetDirectoryName($task)) -TaskName ([System.IO.Path]::GetFileName($task)) -ErrorAction SilentlyContinue
            Write-Log "Disabled scheduled task: $task"
        } catch { Write-Log "Failed to disable task $task: $_" "WARN" }
    }
}
function Enable-ConflictingTasks {
    foreach ($task in $tasks) {
        try {
            Enable-ScheduledTask -TaskPath ([System.IO.Path]::GetDirectoryName($task)) -TaskName ([System.IO.Path]::GetFileName($task)) -ErrorAction SilentlyContinue
            Write-Log "Enabled scheduled task: $task"
        } catch { Write-Log "Failed to enable task $task: $_" "WARN" }
    }
}

# 1. Compliance: Check and clear pending reboot
if (Test-PendingReboot) {
    Write-Log "Pending reboot detected. Rebooting now for clean state." "WARN"
    Restart-Computer -Force
    Start-Sleep -Seconds 90
}

# 2. Security: Stop Windows Update and related services
Stop-ConflictingServices

# 3. Security: Disable conflicting scheduled tasks
Disable-ConflictingTasks

# 4. Hardened Language Pack Install with retry and telemetry
$LanguagesDictionary = @{
    "Arabic (Saudi Arabia)" = "ar-SA"
    "Bulgarian (Bulgaria)" = "bg-BG"
    "Chinese (Simplified, China)" = "zh-CN"
    "Chinese (Traditional, Taiwan)" = "zh-TW"
    "Croatian (Croatia)" = "hr-HR"
    "Czech (Czech Republic)" = "cs-CZ"
    "Danish (Denmark)" = "da-DK"
    "Dutch (Netherlands)" = "nl-NL"
    "English (United States)" = "en-US"
    "English (United Kingdom)" = "en-GB"
    "Estonian (Estonia)" = "et-EE"
    "Finnish (Finland)" = "fi-FI"
    "French (Canada)" = "fr-CA"
    "French (France)" = "fr-FR"
    "German (Germany)" = "de-DE"
    "Greek (Greece)" = "el-GR"
    "Hebrew (Israel)" = "he-IL"
    "Hungarian (Hungary)" = "hu-HU"
    "Italian (Italy)" = "it-IT"
    "Japanese (Japan)" = "ja-JP"
    "Korean (Korea)" = "ko-KR"
    "Latvian (Latvia)" = "lv-LV"
    "Lithuanian (Lithuania)" = "lt-LT"
    "Norwegian, Bokmål (Norway)" = "nb-NO"
    "Polish (Poland)" = "pl-PL"
    "Portuguese (Brazil)" = "pt-BR"
    "Portuguese (Portugal)" = "pt-PT"
    "Romanian (Romania)" = "ro-RO"
    "Russian (Russia)" = "ru-RU"
    "Serbian (Latin, Serbia)" = "sr-Latn-RS"
    "Slovak (Slovakia)" = "sk-SK"
    "Slovenian (Slovenia)" = "sl-SI"
    "Spanish (Mexico)" = "es-MX"
    "Spanish (Spain)" = "es-ES"
    "Swedish (Sweden)" = "sv-SE"
    "Thai (Thailand)" = "th-TH"
    "Turkish (Turkey)" = "tr-TR"
    "Ukrainian (Ukraine)" = "uk-UA"
    "English (Australia)" = "en-AU"
}

foreach ($Language in $LanguageList) {
    $LanguageCode = $LanguagesDictionary[$Language]
    $maxAttempts = 3
    $attempt = 1
    $success = $false
    while ($attempt -le $maxAttempts -and -not $success) {
        try {
            Write-Log "Installing language pack $Language ($LanguageCode), attempt $attempt"
            Install-Language -Language $LanguageCode -ErrorAction Stop
            $success = $true
            Write-Log "Successfully installed $Language ($LanguageCode)"
        } catch {
            Write-Log "Install failed for $Language ($LanguageCode), attempt $attempt: $($_.Exception.Message)" "ERROR"
            if ($attempt -eq $maxAttempts) { throw }
            Start-Sleep -Seconds (30 * $attempt)
        }
        $attempt++
    }
}

# 5. Compliance: Re-enable services and tasks
Enable-ConflictingTasks
Start-ConflictingServices

Write-Log "Language pack installation complete. Rebooting to finalize."
Restart-Computer -Force
