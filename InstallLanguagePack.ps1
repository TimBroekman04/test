param(
    [Parameter(Mandatory)]
    [string]$LangZipUrl,
    [Parameter()]
    [string]$LanguageTag = "nl-NL",
    [Parameter()]
    [string]$TimeZone = "W. Europe Standard Time",
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
    Write-Log "Starting language pack installation for $LanguageTag"
    
    # Disable language pack cleanup tasks
    Write-Log "Disabling language pack cleanup scheduled tasks"
    try {
        Disable-ScheduledTask -TaskPath "\Microsoft\Windows\AppxDeploymentClient\" -TaskName "Pre-staged app cleanup" -ErrorAction SilentlyContinue
        Disable-ScheduledTask -TaskPath "\Microsoft\Windows\MUI\" -TaskName "LPRemove" -ErrorAction SilentlyContinue
        Disable-ScheduledTask -TaskPath "\Microsoft\Windows\LanguageComponentsInstaller" -TaskName "Uninstallation" -ErrorAction SilentlyContinue
    } catch {
        Write-Log "Unable to disable some cleanup tasks: $_" "WARNING"
    }
    
    # Add registry key to prevent language pack cleanup
    if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Control Panel\International")) {
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Control Panel" -Name "International" -Force | Out-Null
    }
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Control Panel\International" -Name "BlockCleanupOfUnusedPreinstalledLangPacks" -Value 1 -Type DWord -Force

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
    $handwritingCab = Get-ChildItem -Path $TempPath -Filter "Microsoft-Windows-LanguageFeatures-Handwriting-${LanguageTag}-Package~*.cab" -Recurse | Select-Object -First 1
    $textToSpeechCab = Get-ChildItem -Path $TempPath -Filter "Microsoft-Windows-LanguageFeatures-TextToSpeech-${LanguageTag}-Package~*.cab" -Recurse | Select-Object -First 1

    if (-not $langPackCab) { Write-Log "Main language pack CAB not found!" "ERROR"; throw }
    if (-not $basicCab)    { Write-Log "Basic FOD CAB not found!" "ERROR"; throw }

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

    # Install OCR FOD if available
    if ($ocrCab) {
        Write-Log "Installing OCR FOD CAB: $($ocrCab.FullName)"
        $dismLog3 = Join-Path $TempPath "DISM_OCRFOD.log"
        $proc3 = Start-Process -FilePath "dism.exe" -ArgumentList "/Online /Add-Package /PackagePath:`"$($ocrCab.FullName)`" /NoRestart /Quiet /LogPath:`"$dismLog3`"" -Wait -PassThru
        if ($proc3.ExitCode -ne 0) {
            Write-Log "DISM failed for $($ocrCab.Name), exit code $($proc3.ExitCode). See $dismLog3" "WARNING"
            # Continue anyway, it's not critical
        }
    }

    # Install optional FODs if available
    if ($handwritingCab) {
        Write-Log "Installing Handwriting FOD CAB: $($handwritingCab.FullName)"
        $dismLog4 = Join-Path $TempPath "DISM_HandwritingFOD.log"
        Start-Process -FilePath "dism.exe" -ArgumentList "/Online /Add-Package /PackagePath:`"$($handwritingCab.FullName)`" /NoRestart /Quiet /LogPath:`"$dismLog4`"" -Wait
    }

    if ($textToSpeechCab) {
        Write-Log "Installing TextToSpeech FOD CAB: $($textToSpeechCab.FullName)"
        $dismLog5 = Join-Path $TempPath "DISM_TextToSpeechFOD.log"
        Start-Process -FilePath "dism.exe" -ArgumentList "/Online /Add-Package /PackagePath:`"$($textToSpeechCab.FullName)`" /NoRestart /Quiet /LogPath:`"$dismLog5`"" -Wait
    }

    # Set Dutch as default everywhere
    Write-Log "Registering $LanguageTag as system, user, and welcome UI language"
    
    # Set user language preferences
    $langList = New-WinUserLanguageList -Language $LanguageTag
    Set-WinUserLanguageList -LanguageList $langList -Force
    
    # Set Windows display language
    Set-WinUILanguageOverride -Language $LanguageTag
    
    # Set system locale
    Set-WinSystemLocale -SystemLocale $LanguageTag
    
    # Set geographical location (Netherlands)
    try {
        Set-WinHomeLocation -GeoId 34
    } catch {
        Write-Log "Unable to set GeoID directly, trying alternative method" "WARNING"
        # Create registry path if it doesn't exist
        if (-not (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\Nls")) {
            New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\" -Name "Nls" -Force | Out-Null
        }
        if (-not (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\Nls\GeoID")) {
            New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Nls\" -Name "GeoID" -Force | Out-Null
        }
        New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Nls\GeoID" -Name "Nation" -Value 34 -PropertyType DWORD -Force | Out-Null
    }
    
    # Set culture (formats, currency, etc.)
    Set-Culture $LanguageTag
    
    # Set timezone
    Set-TimeZone -Id $TimeZone -ErrorAction SilentlyContinue
    
    # Apply settings to welcome screen and new users
    Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true

    # Create unattend.xml for Sysprep to maintain language settings
    Write-Log "Creating unattend.xml to persist language settings through Sysprep"
    $unattendXML = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <InputLocale>$LanguageTag</InputLocale>
            <SystemLocale>$LanguageTag</SystemLocale>
            <UILanguage>$LanguageTag</UILanguage>
            <UILanguageFallback>en-US</UILanguageFallback>
            <UserLocale>$LanguageTag</UserLocale>
        </component>
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
            <TimeZone>$TimeZone</TimeZone>
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                <ProtectYourPC>3</ProtectYourPC>
            </OOBE>
        </component>
    </settings>
</unattend>
"@

    # Save unattend.xml to both possible locations that Sysprep checks
    $unattendPath1 = "$env:SystemRoot\System32\Sysprep\unattend.xml"
    $unattendPath2 = "$env:SystemRoot\Panther\unattend.xml" 
    
    # Create directory if it doesn't exist
    if (-not (Test-Path "$env:SystemRoot\Panther")) {
        New-Item -Path "$env:SystemRoot\Panther" -ItemType Directory -Force | Out-Null
    }
    
    Set-Content -Path $unattendPath1 -Value $unattendXML -Force
    Set-Content -Path $unattendPath2 -Value $unattendXML -Force
    
    Write-Log "Unattend.xml created at $unattendPath1 and $unattendPath2" "SUCCESS"

    # Additional registry entries to ensure Dutch keyboard is set correctly
    Write-Log "Setting additional registry entries for Dutch keyboard layout"
    
    # Set correct keyboard layout
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout" -Name "Keyboard Layout" -Value "00000413" -Type String -Force
    
    # Create logon registry setting to apply language at login
    if (-not (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce")) {
        New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion" -Name "RunOnce" -Force | Out-Null
    }
    
    $applyLangScript = @"
powershell.exe -Command "Set-WinUILanguageOverride -Language $LanguageTag; Set-WinSystemLocale -SystemLocale $LanguageTag; Set-Culture $LanguageTag; Set-WinUserLanguageList $LanguageTag -Force"
"@
    
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" -Name "SetLanguageOnBoot" -Value $applyLangScript -Type String -Force
    Write-Log "Language pack $LanguageTag installed and set as default. Windows requires a reboot for display language to take effect." "SUCCESS"

    # Sysprep readiness - clean component store
    Write-Log "Cleaning up pending language pack operations for Sysprep readiness"
    dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase
}
catch {
    Write-Log "Error: $_" "ERROR"
    exit 1
}
finally {
    # Don't clean up the temp path as it might be needed for troubleshooting
    Write-Log "Installation complete, logs available at $TempPath\LangInstall.log"
}
