param(
    [Parameter(Mandatory=$true)]
    [string]$RegistrationToken
)

Write-Host "Starting AVD Agent installation script."

$uris = @(
    "https://go.microsoft.com/fwlink/?linkid=2310011", # Agent
    "https://go.microsoft.com/fwlink/?linkid=2311028"  # Bootloader
)

$tempPath = $env:TEMP
$installers = @()

foreach ($uri in $uris) {
    try {
        $response = Invoke-WebRequest -Uri $uri -MaximumRedirection 0 -ErrorAction SilentlyContinue
        $expandedUri = $response.Headers.Location
        if (-not $expandedUri) {
            # Handle cases where redirection is not in the header
            $expandedUri = $response.BaseResponse.ResponseUri.AbsoluteUri
        }
        
        $fileName = [System.IO.Path]::GetFileName($expandedUri.Split('?')[0])
        $outFilePath = Join-Path $tempPath $fileName
        
        Write-Host "Downloading $fileName from $expandedUri"
        Invoke-WebRequest -Uri $expandedUri -UseBasicParsing -OutFile $outFilePath
        
        Unblock-File -Path $outFilePath
        $installers += $outFilePath
    }
    catch {
        Write-Error "Failed to download from URI: $uri. Error: $_"
        exit 1
    }
}

Write-Host "`nFiles downloaded:`n$($installers -join "`n")"

$agentInstaller = $installers | Where-Object { $_ -like "*RDAgent.msi" }
$bootloaderInstaller = $installers | Where-Object { $_ -like "*RDAgentBootLoader.msi" }

if (-not $agentInstaller -or -not $bootloaderInstaller) {
    Write-Error "Failed to identify agent and bootloader installers."
    exit 1
}

Write-Host "Installing AVD Agent..."
Start-Process msiexec.exe -Wait -ArgumentList "/i `"$agentInstaller`" /qn REGISTRATIONTOKEN=`"$RegistrationToken`""

Write-Host "Installing AVD Bootloader..."
Start-Process msiexec.exe -Wait -ArgumentList "/i `"$bootloaderInstaller`" /qn"

Write-Host "AVD Agent installation complete."
