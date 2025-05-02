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
    # Mount ISO
    Write-Host "Mounting ISO: $ISOPath"
    $mountResult = Mount-DiskImage -ImagePath $ISOPath -PassThru
    $driveLetter = ($mountResult | Get-Volume).DriveLetter + ':'

    # Install Language Pack
    $langPackPath = "$driveLetter\x64\langpacks\Microsoft-Windows-Client-Language-Pack_x64_$LanguageTag.cab"
    Write-Host "Installing language pack from: $langPackPath"
    dism /Online /Add-Package /PackagePath:"$langPackPath" /LogPath:"$logFile"

    # Install Language Features
    $capabilities = @(
        "Language.Basic~~~$LanguageTag~0.0.1.0",
        "Language.Handwriting~~~$LanguageTag~0.0.1.0",
        "Language.OCR~~~$LanguageTag~0.0.1.0"
    )

    foreach ($cap in $capabilities) {
        Write-Host "Installing capability: $cap"
        dism /Online /Add-Capability /CapabilityName:$cap /Source:"$driveLetter\x64\FOD" /LogPath:"$logFile"
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
    if ($mountResult) {
        Dismount-DiskImage -ImagePath $ISOPath
    }
}
