param(
    [Parameter(Mandatory)]
    [string]$IsoUri,
    [string]$LanguageCode = "nl-NL"
)

# Optimized download with retries
$isoPath = "$env:TEMP\NL-LanguagePack.iso"
$retryCount = 0
do {
    try {
        Start-BitsTransfer -Source $IsoUri -Destination $isoPath -Priority High
        break
    } catch {
        $retryCount++
        Start-Sleep -Seconds (30 * $retryCount)
    }
} while ($retryCount -lt 3)

# Mount with error trapping
try {
    $mount = Mount-DiskImage -ImagePath $isoPath -PassThru -ErrorAction Stop
    $driveLetter = (Get-Volume -DiskImage $mount).DriveLetter + ":\"
} catch {
    Write-Error "Mount failed: $_"
    exit 1
}

# Installation workflow
try {
    # Base language (if missing)
    if (-not (Get-WindowsPackage -Online | Where-Object PackageName -match "Client-Language-Pack_x64_$LanguageCode")) {
        dism.exe /Online /Add-Package /PackagePath:"$driveLetter\x64\langpacks\Microsoft-Windows-Client-Language-Pack_x64_$LanguageCode.cab"
    }

    # Parallel feature install
    $features = @("Handwriting", "TextToSpeech", "OCR")
    $jobs = $features | ForEach-Object {
        Start-ThreadJob -ScriptBlock {
            dism.exe /Online /Add-Package /PackagePath:"$using:driveLetter\Microsoft-Windows-LanguageFeatures-$using:_-$using:LanguageCode-Package~*.cab"
        }
    }
    $jobs | Wait-Job -Timeout 1800 | Receive-Job

    # Post-install validation
    $missing = $requiredPackages | Where-Object { $_ -notin (Get-WindowsPackage -Online).PackageName }
    if ($missing) { throw "Missing packages: $($missing -join ', ')" }

    # System configuration
    Set-WinSystemLocale -SystemLocale $LanguageCode
    Set-WinUILanguageOverride -Language $LanguageCode -Force
    Set-WinHomeLocation -GeoId 176 # Netherlands

} catch {
    Write-Error "Installation failed: $_"
    exit 2
} finally {
    Dismount-DiskImage -ImagePath $isoPath
    Remove-Item $isoPath -Force
}
