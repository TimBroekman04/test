<#
.SYNOPSIS
    Installs language packs and sets the default Windows language robustly for AIB.
.PARAMETER LanguageList
    Array of BCP-47 language tags (e.g. "nl-NL", "fr-FR")
.PARAMETER DefaultLanguage
    The BCP-47 tag to set as the system/user default (e.g. "nl-NL")
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]]$LanguageList,
    [Parameter(Mandatory)]
    [string]$DefaultLanguage
)

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    Write-Host "[$((Get-Date).ToString('s'))][$Level] $Message"
}

function Disable-LanguageTasks {
    Write-Log "Disabling language-related scheduled tasks for servicing reliability."
    Disable-ScheduledTask -TaskPath "\Microsoft\Windows\LanguageComponentsInstaller\" -TaskName "Installation" -ErrorAction SilentlyContinue
    Disable-ScheduledTask -TaskPath "\Microsoft\Windows\LanguageComponentsInstaller\" -TaskName "ReconcileLanguageResources" -ErrorAction SilentlyContinue
    Disable-ScheduledTask -TaskPath "\Microsoft\Windows\MUI\" -TaskName "LPRemove" -ErrorAction SilentlyContinue
    Disable-ScheduledTask -TaskPath "\Microsoft\Windows\AppxDeploymentClient\" -TaskName "Pre-staged app cleanup" -ErrorAction SilentlyContinue
}

function Install-LanguageWithRetry {
    param([string]$LangTag)
    $attempts = 0
    $maxAttempts = 3
    do {
        try {
            Write-Log "Installing language pack [$LangTag] (Attempt $($attempts+1)/$maxAttempts)..."
            Install-Language -Language $LangTag -CopyToSettings -ExcludeFeatures -ErrorAction Stop
            Write-Log "Installed language pack [$LangTag]."
            return $true
        } catch {
            Write-Log "Failed to install [$LangTag]: $_" "WARN"
            Start-Sleep -Seconds (10 * ($attempts+1))
            $attempts++
        }
    } while ($attempts -lt $maxAttempts)
    Write-Log "Giving up on [$LangTag] after $maxAttempts attempts." "ERROR"
    return $false
}

function Set-DefaultLanguage {
    param([string]$LangTag)
    try {
        Write-Log "Setting system and user preferred UI language to [$LangTag]..."
        Set-SystemPreferredUILanguage -Language $LangTag -ErrorAction Stop
        Set-WinUILanguageOverride -Language $LangTag -ErrorAction Stop
        Set-WinUserLanguageList -LanguageList $LangTag -Force -ErrorAction Stop
        Set-WinSystemLocale -SystemLocale $LangTag -ErrorAction Stop
        Set-WinHomeLocation -GeoId (Get-WinUserLanguageList | Where-Object { $_.LanguageTag -eq $LangTag }).GeoId -ErrorAction SilentlyContinue
        Write-Log "Default language set to [$LangTag]."
        return $true
    } catch {
        Write-Log "Failed to set default language [$LangTag]: $_" "ERROR"
        return $false
    }
}

# --- MAIN LOGIC ---

Disable-LanguageTasks

$allSuccess = $true
foreach ($lang in $LanguageList) {
    if (-not (Install-LanguageWithRetry -LangTag $lang)) {
        $allSuccess = $false
    }
}

if ($allSuccess) {
    if (-not (Set-DefaultLanguage -LangTag $DefaultLanguage)) {
        Write-Log "Language packs installed, but failed to set default language." "ERROR"
        exit 1
    }
    Write-Log "All language packs installed and default language set successfully."
    exit 0
} else {
    Write-Log "One or more language packs failed to install." "ERROR"
    exit 1
}
