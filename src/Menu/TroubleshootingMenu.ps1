Clear-Host
Write-Host "Troubleshooting & Validation"
Write-Host "----------------------------"
Write-Host "1) Show install status"
Write-Host "2) System snapshot"
Write-Host "0) Back"

$choice = Read-Host "Select an option"

switch ($choice) {
    "1" { & (Join-Path $PSScriptRoot "..\Tasks\Install-Status.ps1") }
    "2" { & (Join-Path $PSScriptRoot "..\Tasks\System-Snapshot.ps1") }
    "0" { Clear-Host; & (Join-Path $PSScriptRoot "MainMenu.ps1") }
}
