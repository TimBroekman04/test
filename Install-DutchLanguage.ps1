param(
    [Parameter(Mandatory)]
    [string]$IsoUri,
    [string]$LanguageCode = "nl-NL"
)

# Download ISO from storage account
$isoPath = "$env:TEMP\NL-LanguagePack.iso"
try {
    Invoke-WebRequest -Uri $IsoUri -OutFile $isoPath -UseBasicParsing
} catch {
    Write-Error "Failed to download ISO: $_"
    exit 1
}

# Mount ISO
$mountResult = Mount-DiskImage -ImagePath $isoPath -PassThru
$driveLetter = (Get-Volume -DiskImage $mountResult).DriveLetter + ":"

# Install language components
try {
    # Base language pack
    dism.exe /Online /Add-Package /PackagePath:"$driveLetter\x64\langpacks\Microsoft-Windows-Client-Language-Pack_x64_$LanguageCode.cab"
    
    # Optional Features
    $features = @(
        "Handwriting",
        "TextToSpeech",
        "OCR"
    )
    
    foreach ($feature in $features) {
        dism.exe /Online /Add-Package /PackagePath:"$driveLetter\Microsoft-Windows-LanguageFeatures-$feature-$LanguageCode-Package~*.cab"
    }
    
    # Add language to system
    Set-WinUILanguageOverride -Language $LanguageCode
    Set-WinSystemLocale -SystemLocale $LanguageCode
    Set-WinUserLanguageList -LanguageList $LanguageCode -Force
    
} catch {
    Write-Error "DISM operation failed: $_"
    exit 2
} finally {
    # Cleanup
    Dismount-DiskImage -ImagePath $isoPath
    Remove-Item $isoPath -Force
}
