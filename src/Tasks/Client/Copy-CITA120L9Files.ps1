# src\Tasks\Client\Copy-CITA120L9Files.ps1
$ErrorActionPreference = "Stop"

# src\Tasks\Client\ -> up three levels -> repo root
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$zipSrc   = Join-Path $repoRoot "labs\120\CITA120_L9_webpage.zip"

if (-not (Test-Path $zipSrc)) {
    throw "Lab file not found: $zipSrc"
}

$dest = "C:\Users\Public\Desktop\CITA120_L9_webpage.zip"

Copy-Item -Path $zipSrc -Destination $dest -Force

Write-Host ""
Write-Host "Lab file copied to Public Desktop." -ForegroundColor Green
Write-Host "Source: $zipSrc"
Write-Host "Dest:   $dest"
