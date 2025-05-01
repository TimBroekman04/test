param(
    [Parameter(Mandatory)]
    [string]$LangZipUrl,
    [Parameter()]
    [string]$LanguageTag = "nl-NL",
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
    Invoke-WebRequest -Uri $LangZipUrl -OutFile $zipFile -UseBasicParsing

    # Extract ZIP
    Write-Log "Extracting ZIP to $TempPath..."
    Expand-Archive -Path $zipFile -DestinationPath $TempPath -Force
    $LipContent = $TempPath

    # Disable Language Pack Cleanup
    Write-Log "Blocking language pack cleanup scheduled tasks and registry policy"
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Control Panel\International"
    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
    Set-ItemProperty -Path $regPath -Name "BlockCleanupOfUnusedPreinstalledLangPacks" -Value 1 -Type DWord

    $tasks = @(
        "\Microsoft\Windows\AppxDeploymentClient\Pre-staged app cleanup",
        "\Microsoft\Windows\MUI\LPRemove",
        "\Microsoft\Windows\LanguageComponentsInstaller\Uninstallation"
    )
    foreach ($task in $tasks) {
        try {
            Disable-ScheduledTask -TaskPath ($task.Substring(0, $task.LastIndexOf('\')+1)) -TaskName ($task.Split('\')[-1]) -ErrorAction Stop
            Write-Log "Disabled scheduled task: $task"
        } catch {
            Write-Log "Scheduled task $task not found or could not be disabled: $_" "WARNING"
        }
    }

    # Install main language pack CAB using DISM
    $langCab = Get-ChildItem -Path $LipContent -Filter "Microsoft-Windows-Client-Language-Pack_x64_$LanguageTag*.cab" -Recurse | Select-Object -First 1
    if (-not $langCab) { throw "Main language pack CAB not found for $LanguageTag in $LipContent or subfolders" }
    Write-Log "Installing main CAB: $($langCab.FullName)"
    $dismLog = Join-Path $TempPath "DISM_LangPack_$LanguageTag.log"
    $dismArgs = "/Online /Add-Package /PackagePath:`"$($langCab.FullName)`" /NoRestart /Quiet /LogPath:`"$dismLog`""
    $dismRes = Start-Process -FilePath dism.exe -ArgumentList $dismArgs -Wait -PassThru
    if ($dismRes.ExitCode -ne 0) { throw "DISM failed for main CAB. See $dismLog" }

    # Install FODs using Add-WindowsCapability (recommended for 24H2)
    $capabilities = @(
        "Language.Basic~~~$LanguageTag~0.0.1.0",
        "Language.Handwriting~~~$LanguageTag~0.0.1.0",
        "Language.OCR~~~$LanguageTag~0.0.1.0"
    )
    foreach ($capability in $capabilities) {
        Write-Log "Installing capability: $capability"
        try {
            Add-WindowsCapability -Online -Name $capability -Source $LipContent -LimitAccess -ErrorAction Stop
        } catch {
            Write-Log "Failed to install capability $capability $_" "WARNING"
        }
    }

    # Register and set as default everywhere (system/user/welcome/new user)
    Write-Log "Registering $LanguageTag as system, user, and welcome UI language"
    Set-WinUserLanguageList $LanguageTag -Force
    Set-WinUILanguageOverride -Language $LanguageTag
    Set-WinSystemLocale -SystemLocale $LanguageTag
    Set-WinHomeLocation -GeoId 34 
    Set-Culture $LanguageTag
    Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true

    # Remove LXP AppX package if present (prevents conflicts)
    $lxpAppx = Get-AppxPackage -AllUsers | Where-Object { $_.Name -like "Microsoft.LanguageExperiencePacknl-NL*" }
    if ($lxpAppx) {
        Write-Log "Removing LXP AppX package: $($lxpAppx.PackageFullName)"
        Remove-AppxPackage -Package $lxpAppx.PackageFullName -AllUsers
    }

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
