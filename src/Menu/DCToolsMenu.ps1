Clear-Host
Write-Host "Domain Controller Tools"
Write-Host "-----------------------"
Write-Host "1) Install AD DS role (no promotion)"
Write-Host "2) Install DNS role"
Write-Host "3) Install DHCP role"
Write-Host "4) Install Core DC roles"
Write-Host "0) Back"

$choice = Read-Host "Select an option"

switch ($choice) {
    "1" { & (Join-Path $PSScriptRoot "..\Tasks\Install-Roles.ps1") -Mode ADDS }
    "2" { & (Join-Path $PSScriptRoot "..\Tasks\Install-Roles.ps1") -Mode DNS }
    "3" { & (Join-Path $PSScriptRoot "..\Tasks\Install-Roles.ps1") -Mode DHCP }
    "4" { & (Join-Path $PSScriptRoot "..\Tasks\Install-Roles.ps1") -Mode CORE }
}
