Clear-Host
Write-Host "Server Tools"
Write-Host "-------------"
Write-Host "1) Rename computer"
Write-Host "2) Configure static IP"
Write-Host "0) Back"

$choice = Read-Host "Select an option"

switch ($choice) {
    "1" { & (Join-Path $PSScriptRoot "..\Tasks\Rename-Computer.ps1") }
    "2" { & (Join-Path $PSScriptRoot "..\Tasks\Set-StaticIP.ps1") }
    "0" { Clear-Host; & (Join-Path $PSScriptRoot "MainMenu.ps1") }
}
