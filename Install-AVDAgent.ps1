param(
    [Parameter(Mandatory=$true)]
    [string]$RegistrationToken
)

Write-Host "Starting AVD Agent installation script."

# Agent and Bootloader download links
$uris = @{
    Agent      = "https://go.microsoft.com/fwlink/?linkid=2310011"
    Bootloader = "https://go.microsoft.com/fwlink/?linkid=2311028"
}

$tempPath = $env:TEMP
$installers = @{}

# Create a WebClient object for downloading
$webClient = New-Object System.Net.WebClient

foreach ($item in $uris.GetEnumerator()) {
    $name = $item.Name
    $uri = $item.Value
    
    try {
        Write-Host "Downloading AVD $($name)..."
        
        # Discover the actual download URL by following the redirect
        $request = [System.Net.HttpWebRequest]::Create($uri)
        $request.AllowAutoRedirect = $false
        $response = $request.GetResponse()
        $expandedUri = $response.Headers["Location"]
        $response.Close()

        if (-not $expandedUri) {
            throw "Failed to resolve redirect for $uri"
        }

        $fileName = [System.IO.Path]::GetFileName($expandedUri.Split('?')[0])
        $outFilePath = Join-Path $tempPath $fileName
        
        Write-Host "Downloading from $expandedUri to $outFilePath"
        $webClient.DownloadFile($expandedUri, $outFilePath)
        
        Unblock-File -Path $outFilePath
        $installers[$name] = $outFilePath
    }
    catch {
        Write-Error "Failed to download $($name) from URI: $uri. Error: $_"
        exit 1
    }
}

Write-Host "`nFiles downloaded:"
$installers.GetEnumerator() | ForEach-Object { Write-Host "- $($_.Value)" }

# --- CORRECTED INSTALLATION ORDER ---

# 1. Install the Bootloader first
Write-Host "Installing AVD Bootloader..."
Start-Process msiexec.exe -Wait -ArgumentList "/i `"$($installers['Bootloader'])`" /qn"

# 2. Install the Agent with the registration token
Write-Host "Installing AVD Agent..."
Start-Process msiexec.exe -Wait -ArgumentList "/i `"$($installers['Agent'])`" /qn REGISTRATIONTOKEN=`"$RegistrationToken`""

Write-Host "AVD Agent installation complete."
