param(
    [Parameter(Mandatory)]
    [string]$ZipSasUrl,   # SAS-protected URL to the ZIP file
    [Parameter()]
    [string]$LanguageTag = "nl-NL", # Language tag, e.g., nl-NL
    [Parameter()]
    [string]$TempPath = "$env:TEMP\LangPack_$($LanguageTag)"
)

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $msg = "[$timestamp][$Level] $Message"
    Write-Host $msg
    Add-Content -Path "$TempPath\LangInstall.log" -Value $msg
}

# Prep temp folder
if (Test-Path $TempPath) { Remove-Item -Path $TempPath -Recurse -Force }
New-Item -Path $TempPath -ItemType Directory -Force | Out-Null

try {
    # Download ZIP
    $zipFile = Join-Path $TempPath "$LanguageTag-LanguagePack.zip"
    Write-Log "Downloading language pack ZIP from Azure Storage..."
    Invoke-WebRequest -Uri $ZipSasUrl -OutFile $zipFile -UseBasicParsing

    # Extract ZIP
    Write-Log "Extracting ZIP to $TempPath..."
    Expand-Archive -Path $zipFile -DestinationPath $TempPath -Force

    # Find the main language pack CAB
    $langCab = Get-ChildItem -Path $TempPath -Filter "Microsoft-Windows-Client-Language-Pack_x64_$LanguageTag*.cab" -Recurse | Select-Object -First 1
    if (-not $langCab) { throw "Main language pack CAB not found for $LanguageTag in $TempPath or subfolders" }
    Write-Log "Installing main CAB: $($langCab.FullName)"
    $dismLog = Join-Path $TempPath "DISM_LangPack_$LanguageTag.log"
    $dismArgs = "/Online /Add-Package /PackagePath:`"$($langCab.FullName)`" /NoRestart /Quiet /LogPath:`"$dismLog`""
    $dismRes = Start-Process -FilePath dism.exe -ArgumentList $dismArgs -Wait -PassThru
    if ($dismRes.ExitCode -ne 0) { throw "DISM failed for main CAB. See $dismLog" }

    # Install all FOD CABs (Features on Demand)
    $fodCabs = Get-ChildItem -Path $TempPath -Recurse -File | Where-Object {
        $_.Name -like "Microsoft-Windows-LanguageFeatures-*.cab"
    }
    foreach ($fod in $fodCabs) {
        $fodLog = Join-Path $TempPath "DISM_FOD_$($fod.BaseName).log"
        Write-Log "Installing FOD CAB: $($fod.FullName)"
        $fodArgs = "/Online /Add-Package /PackagePath:`"$($fod.FullName)`" /NoRestart /Quiet /LogPath:`"$fodLog`""
        $fodRes = Start-Process -FilePath dism.exe -ArgumentList $fodArgs -Wait -PassThru
        if ($fodRes.ExitCode -ne 0) { Write-Log "DISM failed for FOD CAB $($fod.FullName). See $fodLog" "WARNING" }
    }

    # Register and set as default everywhere (system/user/welcome/new user)
    Write-Log "Registering $LanguageTag as system, user, and welcome UI language"
    # Install-Language is preferred, but fallback to manual registration if not present
    if (Get-Command Install-Language -ErrorAction SilentlyContinue) {
        Install-Language -Language $LanguageTag -CopyToSettings
    }

    Set-WinUserLanguageList $LanguageTag -Force
    Set-WinUILanguageOverride -Language $LanguageTag
    Set-WinSystemLocale -SystemLocale $LanguageTag
    Set-WinHomeLocation -GeoId 34   # 34 = Netherlands
    Set-Culture $LanguageTag
    Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true

    Write-Log "Language pack $LanguageTag installed and set as default. Windows requires a reboot for display language to take effect." "SUCCESS"

    # Sysprep readiness: clean up pending operations
    Write-Log "Cleaning up pending language pack operations for Sysprep readiness"
    dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase
}
catch {
    Write-Log "Error: $_" "ERROR"
    exit 1
}
finally {
    # Clean up temp files
    if (Test-Path $TempPath) { Remove-Item -Path $TempPath -Recurse -Force }
}
