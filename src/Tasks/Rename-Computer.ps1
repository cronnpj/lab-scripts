# src\Tasks\Rename-Computer.ps1
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "..\Lib\Logging.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "..\Lib\Validation.psm1") -Force

Initialize-LabLog
Assert-IsAdmin

$currentName = $env:COMPUTERNAME
Write-Host ""
Write-Host "Current computer name: $currentName"
Write-Host "Recommended: use a clear name (example: DC01 or <username>-DC)"
Write-Host ""

$newName = Read-Host "Enter new computer name"
if ([string]::IsNullOrWhiteSpace($newName)) {
    Write-Host "Cancelled."
    Pause
    return
}

$newName = $newName.Trim()

# Basic validation: Windows computer names are 1-15 chars, no special chars like \ / : * ? " < > |
if ($newName.Length -gt 15) {
    Write-Host "Name too long. Max 15 characters."
    Pause
    return
}
if ($newName -match '[\\\/\:\*\?\"<>\| ]') {
    Write-Host "Invalid characters detected. Avoid spaces and special characters."
    Pause
    return
}
$reservedNames = @('CON','PRN','AUX','NUL','COM1','COM2','COM3','COM4','COM5','COM6','COM7','COM8','COM9','LPT1','LPT2','LPT3','LPT4','LPT5','LPT6','LPT7','LPT8','LPT9')
if ($reservedNames -icontains $newName) {
    Write-Host "Invalid name. '$newName' is a reserved Windows device name."
    Pause
    return
}
if ($newName -ieq $currentName) {
    Write-Host "Name is already $currentName. No change needed."
    Pause
    return
}

Write-Host ""
Write-Host "Rename computer to: $newName"
$confirm = Read-Host "Proceed? (Y/N)"
if ($confirm.Trim().ToUpper() -ne "Y") {
    Write-LabLog "Rename: User cancelled"
    Write-Host "Cancelled."
    Pause
    return
}

Write-LabLog "Rename: Renaming computer from $currentName to $newName"
Rename-Computer -NewName $newName -Force -ErrorAction Stop

Write-Host ""
Write-Host "Rename successful. A reboot is required."
Write-Host "Reboot now?"
$reboot = Read-Host "(Y/N)"
if ($reboot.Trim().ToUpper() -eq "Y") {
    Write-LabLog "Rename: Rebooting now"
    Restart-Computer -Force
} else {
    Write-LabLog "Rename: Reboot deferred by user"
    Write-Host "Please reboot before installing/promoting AD DS."
    Pause
}
