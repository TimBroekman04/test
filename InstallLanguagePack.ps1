param(
    [Parameter(Mandatory)]
    [string]$ImagePath,         # Path to WIM/VHD file
    [Parameter(Mandatory)]
    [string]$MountRoot,         # Mount directory (e.g., C:\Mount)
    [Parameter(Mandatory)]
    [string]$LanguagePackSource # Path to Language ISO or extracted CABs
)

$ErrorActionPreference = 'Stop'
$logPath = "$MountRoot\DISM_Offline.log"

# Helper function for logging
function Write-Log {
    param([string]$Message)
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message" | Out-File $logPath -Append
    Write-Host $Message
}

try {
    # Validate paths
    if (-not (Test-Path $ImagePath)) { throw "Image file not found: $ImagePath" }
    if (-not (Test-Path $LanguagePackSource)) { throw "Language source not found: $LanguagePackSource" }

    # Create mount directory
    if (-not (Test-Path $MountRoot)) { New-Item -Path $MountRoot -ItemType Directory -Force | Out-Null }

    # Mount the image
    Write-Log "Mounting image: $ImagePath"
    $mountResult = dism /Mount-Image /ImageFile:$ImagePath /Index:1 /MountDir:$MountRoot /LogPath:$logPath
    if ($LASTEXITCODE -ne 0) { throw "Mount failed" }

    # Add Dutch language pack
    $langPackPath = Join-Path $LanguagePackSource "Microsoft-Windows-Client-Language-Pack_x64_nl-nl.cab"
    Write-Log "Installing language pack: $langPackPath"
    dism /Image:$MountRoot /Add-Package /PackagePath:$langPackPath /LogPath:$logPath
    if ($LASTEXITCODE -ne 0) { throw "Language pack installation failed" }

    # Add required Features on Demand
    $capabilities = @(
        "Language.Basic~~~nl-NL~0.0.1.0",
        "Language.Handwriting~~~nl-NL~0.0.1.0",
        "Language.OCR~~~nl-NL~0.0.1.0",
        "Language.Speech~~~nl-NL~0.0.1.0",
        "Language.TextToSpeech~~~nl-NL~0.0.1.0"
    )

    foreach ($cap in $capabilities) {
        Write-Log "Adding capability: $cap"
        dism /Image:$MountRoot /Add-Capability /CapabilityName:$cap /Source:$LanguagePackSource /LogPath:$logPath
        if ($LASTEXITCODE -ne 0) { Write-Log "Warning: Failed to add $cap" }
    }

    # Configure regional settings
    Write-Log "Configuring regional settings"
    dism /Image:$MountRoot /Set-SKUIntlDefaults:nl-NL /LogPath:$logPath
    dism /Image:$MountRoot /Set-TimeZone:"W. Europe Standard Time" /LogPath:$logPath

    # Cleanup and optimize
    Write-Log "Optimizing image"
    dism /Image:$MountRoot /Cleanup-Image /StartComponentCleanup /ResetBase /LogPath:$logPath

    # Commit changes
    Write-Log "Unmounting image with commit"
    dism /Unmount-Image /MountDir:$MountRoot /Commit /LogPath:$logPath
}
catch {
    Write-Log "ERROR: $_"
    # Attempt to unmount on failure
    if (Test-Path "$MountRoot\Windows") {
        dism /Unmount-Image /MountDir:$MountRoot /Discard /LogPath:$logPath
    }
    exit 1
}
