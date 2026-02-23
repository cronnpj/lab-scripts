# src\Tasks\Create-Shortcuts.ps1
$ErrorActionPreference = "Stop"

$srcRoot = Split-Path -Parent $PSScriptRoot
$launcherPath = Join-Path $srcRoot "Launch-LabTools.ps1"

if (-not (Test-Path $launcherPath)) {
    throw "Launcher not found: $launcherPath"
}

function New-LabShortcut {
    param(
        [Parameter(Mandatory=$true)][string]$ShortcutPath,
        [Parameter(Mandatory=$true)][string]$LauncherPath,
        [Parameter(Mandatory=$true)][string]$WorkingDirectory
    )

    $shortcutDir = Split-Path -Parent $ShortcutPath
    if (-not (Test-Path $shortcutDir)) {
        New-Item -Path $shortcutDir -ItemType Directory -Force | Out-Null
    }

    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut($ShortcutPath)

    $shortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $shortcut.Arguments = "-NoLogo -ExecutionPolicy Bypass -File `"$LauncherPath`""
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.WindowStyle = 1
    $shortcut.Description = "Launch CITA Lab Tools (Windows Terminal preferred)"
    $shortcut.IconLocation = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe,0"
    $shortcut.Save()
}

$shortcutName = "CITA Lab Tools.lnk"
$desktopPath = [Environment]::GetFolderPath("Desktop")
$startMenuPrograms = Join-Path ([Environment]::GetFolderPath("StartMenu")) "Programs"

$desktopShortcut = Join-Path $desktopPath $shortcutName
$startMenuShortcut = Join-Path $startMenuPrograms $shortcutName
$workingDir = $srcRoot

New-LabShortcut -ShortcutPath $desktopShortcut -LauncherPath $launcherPath -WorkingDirectory $workingDir
New-LabShortcut -ShortcutPath $startMenuShortcut -LauncherPath $launcherPath -WorkingDirectory $workingDir

Write-Host "Shortcuts created/updated:" -ForegroundColor Green
Write-Host " - $desktopShortcut"
Write-Host " - $startMenuShortcut"
