param(
    [Parameter(Mandatory)]
    [string]$LangZipUrl,
    [Parameter()]
    [string]$LanguageTag = "nl-NL",
    [Parameter()]
    [string]$TempPath = "$env:TEMP\LangPack_$($LanguageTag)"
)

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARNING','ERROR','SUCCESS')]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $msg = "[$timestamp][$Level] $Message"
    Write-Host $msg
    Add-Content -Path "$TempPath\LangInstall.log" -Value $msg
}

# --- MAIN EXECUTION ---

if (Test-Path $TempPath) { Remove-Item -Path $TempPath -Recurse -Force }
New-Item -Path $TempPath -ItemType Directory -Force | Out-Null

try {
    # Download and extract
    $zipFile = Join-Path $TempPath "$LanguageTag-LanguagePack.zip"
    Write-Log "Downloading language pack ZIP from Azure Storage..."
    Invoke-WebRequest -Uri $LangZipUrl -OutFile $zipFile -UseBasicParsing

    Write-Log "Extracting ZIP to $TempPath..."
    Expand-Archive -Path $zipFile -DestinationPath $TempPath -Force

    # Find CABs
    $langPackCab = Get-ChildItem -Path $TempPath -Filter "Microsoft-Windows-Client-Language-Pack_x64_${LanguageTag}.cab" -Recurse | Select-Object -First 1
    $basicCab    = Get-ChildItem -Path $TempPath -Filter "Microsoft-Windows-LanguageFeatures-Basic-${LanguageTag}-Package~*.cab" -Recurse | Select-Object -First 1
    $ocrCab      = Get-ChildItem -Path $TempPath -Filter "Microsoft-Windows-LanguageFeatures-OCR-${LanguageTag}-Package~*.cab" -Recurse | Select-Object -First 1

    if (-not $langPackCab) { Write-Log "Main language pack CAB not found!" "ERROR"; throw }
    if (-not $basicCab)    { Write-Log "Basic FOD CAB not found!" "ERROR"; throw }
    if (-not $ocrCab)      { Write-Log "OCR FOD CAB not found!" "ERROR"; throw }

    # Install main language pack
    Write-Log "Installing main language pack CAB: $($langPackCab.FullName)"
    $dismLog1 = Join-Path $TempPath "DISM_LangPack.log"
    $proc1 = Start-Process -FilePath "dism.exe" -ArgumentList "/Online /Add-Package /PackagePath:`"$($langPackCab.FullName)`" /NoRestart /Quiet /LogPath:`"$dismLog1`"" -Wait -PassThru
    if ($proc1.ExitCode -ne 0) {
        Write-Log "DISM failed for $($langPackCab.Name), exit code $($proc1.ExitCode). See $dismLog1" "ERROR"
        throw
    }

    # Install Basic FOD
    Write-Log "Installing Basic FOD CAB: $($basicCab.FullName)"
    $dismLog2 = Join-Path $TempPath "DISM_BasicFOD.log"
    $proc2 = Start-Process -FilePath "dism.exe" -ArgumentList "/Online /Add-Package /PackagePath:`"$($basicCab.FullName)`" /NoRestart /Quiet /LogPath:`"$dismLog2`"" -Wait -PassThru
    if ($proc2.ExitCode -ne 0) {
        Write-Log "DISM failed for $($basicCab.Name), exit code $($proc2.ExitCode). See $dismLog2" "ERROR"
        throw
    }

    # Install OCR FOD
    Write-Log "Installing OCR FOD CAB: $($ocrCab.FullName)"
    $dismLog3 = Join-Path $TempPath "DISM_OCRFOD.log"
    $proc3 = Start-Process -FilePath "dism.exe" -ArgumentList "/Online /Add-Package /PackagePath:`"$($ocrCab.FullName)`" /NoRestart /Quiet /LogPath:`"$dismLog3`"" -Wait -PassThru
    if ($proc3.ExitCode -ne 0) {
        Write-Log "DISM failed for $($ocrCab.Name), exit code $($proc3.ExitCode). See $dismLog3" "ERROR"
        throw
    }

    # Set Dutch as default everywhere
    Write-Log "Registering $LanguageTag as system, user, and welcome UI language"
    Set-WinUserLanguageList $LanguageTag -Force
    Set-WinUILanguageOverride -Language $LanguageTag
    Set-WinSystemLocale -SystemLocale $LanguageTag
    Set-WinHomeLocation -GeoId 34
    Set-Culture $LanguageTag
    Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true

    Write-Log "Language pack $LanguageTag installed and set as default. Windows requires a reboot for display language to take effect." "SUCCESS"

    # Sysprep readiness
    Write-Log "Cleaning up pending language pack operations for Sysprep readiness"
    dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase
}
catch {
    Write-Log "Error: $_" "ERROR"
    exit 1
}
finally {
    if (Test-Path $TempPath) { Remove-Item -Path $TempPath -Recurse -Force }
}
