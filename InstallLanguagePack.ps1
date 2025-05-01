param(
    [Parameter(Mandatory)]
    [string]$LanguageTag, # e.g. 'nl-NL'
    [Parameter(Mandatory)]
    [string]$ZipSasUrl,   # SAS-protected URL to the language pack ZIP in Azure Storage
    [Parameter()]
    [string]$TempPath = "$env:TEMP\LangInstall"
)

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $msg = "[$timestamp][$Level] $Message"
    Write-Host $msg
    Add-Content -Path "$TempPath\LangInstall.log" -Value $msg
}

# Ensure temp path is clean
if (Test-Path $TempPath) { Remove-Item -Path $TempPath -Recurse -Force }
New-Item -Path $TempPath -ItemType Directory -Force | Out-Null

try {
    # Download ZIP from Azure Storage
    $zipFile = Join-Path $TempPath "$LanguageTag-LanguagePack.zip"
    Write-Log "Downloading language pack ZIP from Azure Storage..."
    Invoke-WebRequest -Uri $ZipSasUrl -OutFile $zipFile -UseBasicParsing

    # Extract ZIP
    Write-Log "Extracting ZIP to $TempPath..."
    Expand-Archive -Path $zipFile -DestinationPath $TempPath -Force

    # Disable language pack cleanup
    Write-Log "Disabling language pack cleanup scheduled tasks..."
    Disable-ScheduledTask -TaskPath "\Microsoft\Windows\AppxDeploymentClient\" -TaskName "Pre-staged app cleanup" -ErrorAction SilentlyContinue
    Disable-ScheduledTask -TaskPath "\Microsoft\Windows\MUI\" -TaskName "LPRemove" -ErrorAction SilentlyContinue
    Disable-ScheduledTask -TaskPath "\Microsoft\Windows\LanguageComponentsInstaller" -TaskName "Uninstallation" -ErrorAction SilentlyContinue
    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Control Panel\International" -Force | Out-Null
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Control Panel\International" -Name "BlockCleanupOfUnusedPreinstalledLangPacks" -Value 1 -Type DWord

    # Install main language pack CAB
    $langCab = Get-ChildItem -Path $TempPath -Filter "*$LanguageTag*.cab" | Where-Object { $_.Name -like "*Client-Language-Pack*" } | Select-Object -First 1
    if (-not $langCab) { throw "Main language pack CAB not found for $LanguageTag in $TempPath" }
    Write-Log "Installing main CAB: $($langCab.Name)"
    $dismLog = Join-Path $TempPath "DISM_LangPack_$LanguageTag.log"
    $dismArgs = "/Online /Add-Package /PackagePath:`"$($langCab.FullName)`" /NoRestart /Quiet /LogPath:`"$dismLog`""
    $dismRes = Start-Process -FilePath dism.exe -ArgumentList $dismArgs -Wait -PassThru
    if ($dismRes.ExitCode -ne 0) { throw "DISM failed for main CAB. See $dismLog" }

    # Install all FODs (Features on Demand)
    $fodCabs = Get-ChildItem -Path $TempPath -Filter "*$LanguageTag*.cab" | Where-Object { $_.Name -notlike "*Client-Language-Pack*" }
    foreach ($fod in $fodCabs) {
        $fodLog = Join-Path $TempPath "DISM_FOD_$($fod.BaseName).log"
        Write-Log "Installing FOD CAB: $($fod.Name)"
        $fodArgs = "/Online /Add-Package /PackagePath:`"$($fod.FullName)`" /NoRestart /Quiet /LogPath:`"$fodLog`""
        $fodRes = Start-Process -FilePath dism.exe -ArgumentList $fodArgs -Wait -PassThru
        if ($fodRes.ExitCode -ne 0) { throw "DISM failed for FOD CAB $($fod.Name). See $fodLog" }
    }

    # Install Local Experience Pack APPX if present
    $lepAppx = Get-ChildItem -Path $TempPath -Filter "*LanguageExperiencePack.$LanguageTag*.appx" | Select-Object -First 1
    if ($lepAppx) {
        Write-Log "Installing Local Experience Pack APPX: $($lepAppx.Name)"
        Add-AppxProvisionedPackage -Online -PackagePath $lepAppx.FullName -SkipLicense -ErrorAction Stop
    }

    # Register language for user/system
    Write-Log "Registering $LanguageTag as system and user UI language"
    $langList = Get-WinUserLanguageList
    if (-not ($langList.LanguageTag -contains $LanguageTag)) {
        $langList.Add($LanguageTag)
        Set-WinUserLanguageList $langList -Force
    }
    Set-SystemPreferredUILanguage -Language $LanguageTag
    Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true

    Write-Log "Language pack $LanguageTag installed successfully." "SUCCESS"
}
catch {
    Write-Log "Error: $_" "ERROR"
    exit 1
}
finally {
    # Clean up temp files
    if (Test-Path $TempPath) { Remove-Item -Path $TempPath -Recurse -Force }
}
