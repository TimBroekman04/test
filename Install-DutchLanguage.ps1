param(
    [Parameter(Mandatory)]
    [string]$ISOPath,
    
    [Parameter(Mandatory)]
    [string]$LanguageTag,
    
    [string]$TempPath = "C:\LangInstall"
)

$ErrorActionPreference = 'Stop'
$logFile = "$TempPath\DISM_Offline.log"

try {
    # Create temp directory
    if (-not (Test-Path $TempPath)) {
        New-Item -Path $TempPath -ItemType Directory -Force | Out-Null
    }

    # Mount ISO
    Write-Host "Mounting ISO: $ISOPath"
    Mount-DiskImage -ImagePath $ISOPath
    $driveLetter = (Get-DiskImage -ImagePath $ISOPath | Get-Volume).DriveLetter + ':'

    # Validate ISO structure
    if (-not (Test-Path "$driveLetter\x64\langpacks")) {
        throw "Invalid ISO structure - missing langpacks directory"
    }

    # Install Language Pack
    $langPackPath = "$driveLetter\x64\langpacks\Microsoft-Windows-Client-Language-Pack_x64_$LanguageTag.cab"
    Write-Host "Installing language pack from: $langPackPath"
    dism /Online /Add-Package /PackagePath:"$langPackPath" /LogPath:"$logFile" /English

    # Install Language Features
    $capabilities = @(
        "Language.Basic~~~$LanguageTag~0.0.1.0",
        "Language.Handwriting~~~$LanguageTag~0.0.1.0",
        "Language.OCR~~~$LanguageTag~0.0.1.0"
    )

    foreach ($cap in $capabilities) {
        Write-Host "Installing capability: $cap"
        dism /Online /Add-Capability /CapabilityName:$cap /Source:"$driveLetter\x64\FOD" /LogPath:"$logFile" /English
    }

    # Configure regional settings
    Set-WinSystemLocale -SystemLocale $LanguageTag
    Set-WinUILanguageOverride -Language $LanguageTag
    Set-TimeZone -Id "W. Europe Standard Time"

    # Persist settings for new users
    Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true

    # Cleanup
    dism /Online /Cleanup-Image /StartComponentCleanup /ResetBase /LogPath:"$logFile"
}
catch {
    Write-Host "Error occurred: $_"
    exit 1
}
finally {
    # Dismount ISO
    if ($driveLetter) {
        Dismount-DiskImage -ImagePath $ISOPath
    }
}
