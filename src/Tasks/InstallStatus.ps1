# src\Tasks\Show-InstallStatus.ps1
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "..\Lib\Logging.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "..\Lib\Validation.psm1") -Force

Initialize-LabLog
Assert-IsAdmin

Write-LabLog "Status: Showing install status"

$states = Get-RoleInstallState -FeatureNames @("AD-Domain-Services", "DNS", "DHCP")

Write-Host ""
Write-Host "Installed Roles/Features:"
$states | Format-Table -AutoSize
Write-Host ""
Write-Host ("Log: {0}" -f (Get-LabLogPath))
