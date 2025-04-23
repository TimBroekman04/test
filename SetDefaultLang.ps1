<#
.SYNOPSIS
    Sets the default system language, locale, and region robustly for AIB.
.PARAMETER Language
    Language name (e.g. "Dutch (Netherlands)" or "nl-NL")
#>
param(
    [Parameter(Mandatory)]
    [string]$Language
)

function Write-Log { param($msg, $lvl = "INFO") ; Write-Host "[$((Get-Date).ToString('s'))][$lvl] $msg" }

# Convert friendly name to locale if needed
$locale = switch ($Language) {
    "Dutch (Netherlands)" { "nl-NL" }
    default { $Language }
}

Write-Log "Setting system language and region to $locale"

# Set system locale, region, and user language list
Set-WinSystemLocale $locale
Set-WinHomeLocation -GeoId 0xb0 # Netherlands
Set-Culture $locale
Set-WinUserLanguageList $locale -Force

# Copy to all users (system default)
Copy-UserInternationalSettingsToSystem -WelcomeScreen $false -NewUser $true

# Set registry values for region, timezone, etc.
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language" -Name "InstallLanguage" -Value "0413"
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language" -Name "Default" -Value "0413"
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language" -Name "DefaultUserLocale" -Value "0413"
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language" -Name "DefaultSystemLocale" -Value "0413"

Write-Log "System language and region set to $locale"

exit 0
