param(
    [Parameter(Mandatory)]
    [string]$ZipUrl,  # SAS-protected URL to NL-LanguagePack.zip in Azure Storage
    [Parameter(Mandatory=$false)]
    [string]$TempPath = "$env:TEMP\NL-LanguagePack"
)

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    Write-Host "[$Level] $Message"
}

try {
    # Ensure temp path is clean
    if (Test-Path $TempPath) { Remove-Item -Path $TempPath -Recurse -Force }
    New-Item -Path $TempPath -ItemType Directory -Force | Out-Null

    $zipFile = Join-Path $TempPath "NL-LanguagePack.zip"

    Write-Log "Downloading Dutch language pack ZIP from Azure Storage..."
    Invoke-WebRequest -Uri $ZipUrl -OutFile $zipFile -UseBasicParsing

    Write-Log "Extracting ZIP to $TempPath..."
    Expand-Archive -Path $zipFile -DestinationPath $TempPath -Force

    # Path to extracted CABs and APPX
    $cabPath = $TempPath

    # Disable language pack cleanup tasks to prevent removal during OOBE
    Write-Log "Disabling language pack cleanup scheduled tasks..."
    Disable-ScheduledTask -TaskPath "\Microsoft\Windows\AppxDeploymentClient\" -TaskName "Pre-staged app cleanup" -ErrorAction SilentlyContinue
    Disable-ScheduledTask -TaskPath "\Microsoft\Windows\MUI\" -TaskName "LPRemove" -ErrorAction SilentlyContinue
    Disable-ScheduledTask -TaskPath "\Microsoft\Windows\LanguageComponentsInstaller" -TaskName "Uninstallation" -ErrorAction SilentlyContinue
    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Control Panel\International" -Force | Out-Null
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Control Panel\International" -Name "BlockCleanupOfUnusedPreinstalledLangPacks" -Value 1 -Type DWord

    # Install the main language pack CAB
    $langCab = Get-ChildItem -Path $cabPath -Filter "*nl-nl*.cab" | Where-Object { $_.Name -like "*Client-Language-Pack*" } | Select-Object -First 1
    if ($langCab) {
        Write-Log "Installing main Dutch language pack CAB: $($langCab.Name)"
        Add-WindowsPackage -Online -PackagePath $langCab.FullName -NoRestart
    } else {
        throw "Dutch language pack CAB not found in $cabPath"
    }

    # Install additional FODs (Basic, OCR, Handwriting, etc.)
    $fodCabs = Get-ChildItem -Path $cabPath -Filter "*nl-nl*.cab" | Where-Object { $_.Name -notlike "*Client-Language-Pack*" }
    foreach ($fod in $fodCabs) {
        Write-Log "Installing FOD CAB: $($fod.Name)"
        Add-WindowsPackage -Online -PackagePath $fod.FullName -NoRestart
    }

    # Install Local Experience Pack APPX if present
    $lepAppx = Get-ChildItem -Path $cabPath -Filter "*LanguageExperiencePack.nl-nl*.appx" | Select-Object -First 1
    if ($lepAppx) {
        Write-Log "Installing Local Experience Pack APPX: $($lepAppx.Name)"
        Add-AppProvisionedPackage -Online -PackagePath $lepAppx.FullName
    }

    # Register the language in Windows
    Write-Log "Registering Dutch language in user language list..."
    $LanguageList = Get-WinUserLanguageList
    if (-not ($LanguageList.LanguageTag -contains "nl-NL")) {
        $LanguageList.Add("nl-NL")
        Set-WinUserLanguageList $LanguageList -Force
    }

    # Set system preferred UI language
    Set-SystemPreferredUILanguage -Language "nl-NL"
    Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true

    Write-Log "Dutch language pack installation completed successfully." "SUCCESS"
}
catch {
    Write-Log "Error during Dutch language pack installation: $_" "ERROR"
    exit 1
}
finally {
    # Clean up temp files
    if (Test-Path $TempPath) { Remove-Item -Path $TempPath -Recurse -Force }
}
