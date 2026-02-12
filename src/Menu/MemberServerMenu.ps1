Clear-Host
Write-Host "Member Server Tools"
Write-Host "-------------------"
Write-Host "1) Join existing domain"
Write-Host "0) Back"

$choice = Read-Host "Select an option"

switch ($choice) {
    "1" { & (Join-Path $PSScriptRoot "..\Tasks\Join-Domain.ps1") }
}
