$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$srcPath  = Join-Path $repoRoot "src"
$distPath = Join-Path $repoRoot "dist"
$versionFile = Join-Path $srcPath "VERSION.txt"

if (-not (Test-Path $versionFile)) {
    throw "VERSION.txt not found in src folder."
}

$version = (Get-Content $versionFile).Trim()

if (-not (Test-Path $distPath)) {
    New-Item -Path $distPath -ItemType Directory | Out-Null
}

$zipName = "CITA-LabTools-$version.zip"
$zipPath = Join-Path $distPath $zipName

if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}

Write-Host "Building package: $zipName"

Compress-Archive -Path "$srcPath\*" -DestinationPath $zipPath

Write-Host "Package created:"
Write-Host $zipPath
