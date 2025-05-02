param(
    [Parameter(Mandatory)]
    [string]$LanguageSource,
    
    [Parameter(Mandatory)]
    [string]$LanguageTag,
    
    [string]$TempPath = "C:\LangInstall"
)

$ErrorActionPreference = 'Stop'
$logFile = "$TempPath\DISM_Offline.log"

# Create temp directory if not exists
if (-not (Test-Path $TempPath)) {
    New-Item -Path $TempPath -ItemType Directory -Force | Out-Null
}

try {
    # Install Language Pack
    $langPackPath = Join-Path $LanguageSource "langpacks\Microsoft-Windows-Client-Language-Pack_x64_$LanguageTag.cab"
    Write-Host "Installing language pack from: $langPackPath"
    dism /Online /Add-Package /PackagePath:"$langPackPath" /LogPath:"$logFile" /English

    # Install Basic Language Features
    $capabilities = @(
        "Language.Basic~~~$LanguageTag~0.0.1.0",
        "Language.Handwriting~~~$LanguageTag~0.0.1.0",
        "Language.OCR~~~$LanguageTag~0.0.1.0"
    )

    foreach ($cap in $capabilities) {
        Write-Host "Installing capability: $cap"
        dism /Online /Add-Capability /CapabilityName:$cap /Source:"$LanguageSource\FOD" /LogPath:"$logFile" /English
    }

    # Set Regional Settings
    Set-WinSystemLocale -SystemLocale $LanguageTag
    Set-WinUILanguageOverride -Language $LanguageTag
    Set-TimeZone -Id "W. Europe Standard Time"

    # Persist settings for new users
    Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true

    # Finalize changes
    dism /Online /Cleanup-Image /StartComponentCleanup /ResetBase /LogPath:"$logFile"
}
catch {
    Write-Host "Error occurred: $_"
    exit 1
}
