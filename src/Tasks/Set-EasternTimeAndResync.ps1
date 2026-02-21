$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "..\Lib\Logging.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "..\Lib\Validation.psm1") -Force

Initialize-LabLog
Assert-IsAdmin

function Wait-MenuContinue {
    Write-Host ""
    Read-Host "Press Enter to continue" | Out-Null
}

Write-Host ""
Write-Host "Set Timezone to Eastern and Resync Clock"
Write-Host "-----------------------------------------"

$targetTimezoneId = "Eastern Standard Time"
$currentTimezone = Get-TimeZone

if ($currentTimezone.Id -ne $targetTimezoneId) {
    Write-LabLog "Time: Changing timezone from $($currentTimezone.Id) to $targetTimezoneId"
    Set-TimeZone -Id $targetTimezoneId -ErrorAction Stop
    Write-Host "Timezone updated to Eastern Standard Time."
} else {
    Write-LabLog "Time: Timezone already set to $targetTimezoneId"
    Write-Host "Timezone is already Eastern Standard Time."
}

$w32timeService = Get-Service -Name "w32time" -ErrorAction SilentlyContinue
if ($null -ne $w32timeService -and $w32timeService.Status -ne "Running") {
    Write-LabLog "Time: Starting Windows Time service"
    Start-Service -Name "w32time" -ErrorAction SilentlyContinue
}

Write-LabLog "Time: Running w32tm /resync /force"
$resyncOutput = & w32tm /resync /force 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "Clock resync completed."
    Write-LabLog "Time: Clock resync completed"
} else {
    Write-Host "Clock resync returned a non-zero exit code."
    Write-Host "Output:"
    $resyncOutput | ForEach-Object { Write-Host $_ }
    Write-LabLog ("Time: Clock resync non-zero exit ({0}). Output: {1}" -f $LASTEXITCODE, ($resyncOutput -join " ")) "WARN"
}

$updatedTimezone = Get-TimeZone
Write-Host ""
Write-Host ("Current timezone: {0} ({1})" -f $updatedTimezone.DisplayName, $updatedTimezone.Id)
Write-Host ("Log: {0}" -f (Get-LabLogPath))

Wait-MenuContinue
