Clear-Host
Write-Host "Maintenance & Updates"
Write-Host "---------------------"
Write-Host "1) Update Lab Tools from GitHub"
Write-Host "0) Back"

$choice = Read-Host "Select an option"

switch ($choice) {
    "1" { & (Join-Path $PSScriptRoot "..\Tasks\Update-LabTools.ps1") }
}
