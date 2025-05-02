param(
    [Parameter(Mandatory)]
    [string]$IsoSasUrl
)

$isoPath = "$env:TEMP\$(Split-Path $IsoSasUrl -Leaf)"

try {
    # Download ISO using SAS token
    Invoke-WebRequest -Uri $IsoSasUrl -OutFile $isoPath -UseBasicParsing

    # Mount ISO and install language
    $mountResult = Mount-DiskImage -ImagePath $isoPath -PassThru
    $driveLetter = ($mountResult | Get-Volume).DriveLetter + ":"

    # DISM commands
    dism /online /add-package /packagepath:"$driveLetter\LanguagesAndOptionalFeatures\Microsoft-Windows-Client-Language-Pack_x64_nl-nl.cab"
    
    # Regional settings
    Set-WinSystemLocale -SystemLocale nl-NL
    Set-WinHomeLocation -GeoId 176
    Set-WinUILanguageOverride -Language nl-NL
    
    # Language features
    dism /online /add-capability /name:Language.Handwriting~~~nl-NL~0.0.1.0
    dism /online /add-capability /name:Language.OCR~~~nl-NL~0.0.1.0
}
finally {
    if (Test-Path $isoPath) {
        Dismount-DiskImage -ImagePath $isoPath
        Remove-Item $isoPath -Force
    }
    
    # Verification
    if ((Get-WinUserLanguageList).LanguageTag -notcontains "nl-NL") {
        throw "Language installation verification failed"
    }
}
