param(
    [Parameter(Mandatory)]
    [string]$LanguageTag, # e.g. 'nl-NL'
    [Parameter(Mandatory)]
    [string]$SourcePath,  # e.g. '\\fileserver\langpacks\nl-NL'
    [Parameter()]
    [string]$LogDir = "$env:SystemDrive\Logs\LangInstall"
)

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $msg = "[$timestamp][$Level] $Message"
    Write-Host $msg
    Add-Content -Path (Join-Path $LogDir "LangInstall.log") -Value $msg
}

# Ensure log directory exists
if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory | Out-Null }

try {
    Write-Log "Starting language pack installation for $LanguageTag from $SourcePath"

    # Find main language pack CAB (Client-Language-Pack)
    $langCab = Get-ChildItem -Path $SourcePath -Filter "*$LanguageTag*.cab" | Where-Object { $_.Name -like "*Client-Language-Pack*" } | Select-Object -First 1
    if (-not $langCab) { throw "Main language pack CAB not found for $LanguageTag in $SourcePath" }
    $logCab = Join-Path $LogDir "DISM_LangPack_$($LanguageTag).log"
    Write-Log "Installing main CAB: $($langCab.Name)"
    $dismArgs = "/Online /Add-Package /PackagePath:`"$($langCab.FullName)`" /NoRestart /Quiet /LogPath:`"$logCab`""
    $dismRes = Start-Process -FilePath dism.exe -ArgumentList $dismArgs -Wait -PassThru
    if ($dismRes.ExitCode -ne 0) { throw "DISM failed for main CAB. See $logCab" }

    # Install all FODs (Features on Demand) for this language
    $fodCabs = Get-ChildItem -Path $SourcePath -Filter "*$LanguageTag*.cab" | Where-Object { $_.Name -notlike "*Client-Language-Pack*" }
    foreach ($fod in $fodCabs) {
        $fodLog = Join-Path $LogDir "DISM_FOD_$($fod.BaseName).log"
        Write-Log "Installing FOD CAB: $($fod.Name)"
        $fodArgs = "/Online /Add-Package /PackagePath:`"$($fod.FullName)`" /NoRestart /Quiet /LogPath:`"$fodLog`""
        $fodRes = Start-Process -FilePath dism.exe -ArgumentList $fodArgs -Wait -PassThru
        if ($fodRes.ExitCode -ne 0) { throw "DISM failed for FOD CAB $($fod.Name). See $fodLog" }
    }

    # Install Local Experience Pack APPX if present
    $lepAppx = Get-ChildItem -Path $SourcePath -Filter "*LanguageExperiencePack.$LanguageTag*.appx" | Select-Object -First 1
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
