$ErrorActionPreference = 'Stop'

# These files must come from the same Drift release as the Dart dependency.
$driftVersion = '2.35.4'
$releaseBase = "https://github.com/simolus3/drift/releases/download/drift-$driftVersion"
$webDirectory = Join-Path (Split-Path -Parent $PSScriptRoot) 'web'

$assets = @(
    @{
        Name = 'sqlite3.wasm'
        Sha256 = 'e7451780e78c56ff864fe9317a0fbcd6aeb2e8de3beba7f5efd963202f7ec3d9'
    },
    @{
        Name = 'drift_worker.js'
        Sha256 = '48c950cd8e3bc3cddb34816c860e228be8832bef07a297c27e9907c057ff8162'
    }
)

New-Item -ItemType Directory -Force -Path $webDirectory | Out-Null

foreach ($asset in $assets) {
    $destination = Join-Path $webDirectory $asset.Name
    $downloadUrl = "$releaseBase/$($asset.Name)"

    Write-Host "Downloading $($asset.Name) from Drift $driftVersion..."
    Invoke-WebRequest -Uri $downloadUrl -OutFile $destination -UseBasicParsing

    $actualHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $asset.Sha256) {
        Remove-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
        throw "SHA-256 verification failed for $($asset.Name). The downloaded file was removed."
    }

    Write-Host "Verified $($asset.Name)"
}

Write-Host ''
Write-Host 'Drift Web assets are installed and checksum-verified.' -ForegroundColor Green
