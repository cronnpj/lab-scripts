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

$workingDir = $srcRoot
$shortcutNames = @(
    "CITA Lab Tools.lnk",
    "CITA Server Setup.lnk"
)

$locations = @(
    [pscustomobject]@{ Label = "CurrentUser Desktop"; Path = [Environment]::GetFolderPath("Desktop") },
    [pscustomobject]@{ Label = "CurrentUser StartMenu"; Path = (Join-Path ([Environment]::GetFolderPath("StartMenu")) "Programs") },
    [pscustomobject]@{ Label = "AllUsers Desktop"; Path = [Environment]::GetFolderPath("CommonDesktopDirectory") },
    [pscustomobject]@{ Label = "AllUsers StartMenu"; Path = (Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs") }
)

$created = @()
$failed = @()

foreach ($location in $locations) {
    if (-not $location.Path) { continue }

    foreach ($shortcutName in $shortcutNames) {
        $shortcutPath = Join-Path $location.Path $shortcutName

        try {
            New-LabShortcut -ShortcutPath $shortcutPath -LauncherPath $launcherPath -WorkingDirectory $workingDir
            $created += "[$($location.Label)] $shortcutPath"
        }
        catch {
            $failed += "[$($location.Label)] $shortcutPath :: $($_.Exception.Message)"
        }
    }
}

if ($created.Count -gt 0) {
    Write-Host "Shortcuts created/updated:" -ForegroundColor Green
    $created | ForEach-Object { Write-Host " - $_" }
}

if ($failed.Count -gt 0) {
    Write-Host ""
    Write-Host "Some shortcut writes failed (likely permissions on all-users locations):" -ForegroundColor DarkYellow
    $failed | ForEach-Object { Write-Host " - $_" -ForegroundColor DarkYellow }
}
