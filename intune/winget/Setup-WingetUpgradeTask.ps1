# Setup-WingetUpgradeTask.ps1
# Deploy via Intune Platform Scripts (run with logged-on user credentials)
# Creates a scheduled task that runs winget upgrade --all daily at 2am
# NOTE: In Intune, set "Run this script using the logged on credentials" = Yes

$taskName   = "WingetUpgradeAll"
$logDir     = "C:\ProgramData\WingetUpgrade"
$scriptPath = "$logDir\Run-WingetUpgrade.ps1"

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# Write the upgrade script to disk
Set-Content -Path $scriptPath -Force -Value @'
$logDir  = "C:\ProgramData\WingetUpgrade"
$logFile = "$logDir\upgrade.log"

Add-Content -Path $logFile -Value "`n=== $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="

# Resolve winget — works reliably in user context
$wingetExe = Get-ChildItem "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*\winget.exe" `
    -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending |
    Select-Object -First 1 -ExpandProperty FullName

if (-not $wingetExe) {
    Add-Content -Path $logFile -Value "ERROR: winget.exe not found"
    exit 1
}

Add-Content -Path $logFile -Value "winget: $wingetExe"

# Update sources first so package list is current
& $wingetExe source update --disable-interactivity 2>&1 | Out-Null

$output = & $wingetExe upgrade --all --silent --accept-package-agreements --accept-source-agreements --include-unknown 2>&1
Add-Content -Path $logFile -Value ($output | Out-String)
Add-Content -Path $logFile -Value "=== Done ==="
'@

# Remove existing task if present
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""

$trigger = New-ScheduledTaskTrigger -Daily -At "2:00AM"

$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1) `
    -RunOnlyIfNetworkAvailable $true `
    -StartWhenAvailable $true

# Run as logged-on user (any member of the Users group) instead of SYSTEM
# This is required for winget to authenticate to package sources correctly
$principal = New-ScheduledTaskPrincipal `
    -GroupId "BUILTIN\Users" `
    -RunLevel Highest

Register-ScheduledTask `
    -TaskName   $taskName `
    -Action     $action `
    -Trigger    $trigger `
    -Settings   $settings `
    -Principal  $principal `
    -Description "Daily winget upgrade for all packages (runs as logged-on user)" | Out-Null

Write-Output "Scheduled task '$taskName' registered. Logs: $logDir\upgrade.log"