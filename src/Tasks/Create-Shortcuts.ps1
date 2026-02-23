# src\Tasks\Create-Shortcuts.ps1
$ErrorActionPreference = "Stop"

$srcRoot = Split-Path -Parent $PSScriptRoot
$launcherPath = Join-Path $srcRoot "Launch-LabTools.ps1"
$configPath = Join-Path $srcRoot "config\labtools.json"

if (-not (Test-Path $launcherPath)) {
    throw "Launcher not found: $launcherPath"
}

function Test-IsElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function New-LabShortcut {
    param(
        [Parameter(Mandatory=$true)][string]$ShortcutPath,
        [Parameter(Mandatory=$true)][string]$LauncherPath,
        [Parameter(Mandatory=$true)][string]$WorkingDirectory,
        [Parameter(Mandatory=$true)][string]$IconLocation
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
    $shortcut.IconLocation = $IconLocation
    $shortcut.Save()
}

$workingDir = $srcRoot
$createPublicDesktopShortcuts = $false
$defaultIconLocation = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe,0"
$shortcutIconLocation = $defaultIconLocation
$isElevated = Test-IsElevated

if (Test-Path $configPath) {
    try {
        $config = Get-Content -Path $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $config.shortcuts -and $null -ne $config.shortcuts.createPublicDesktopShortcuts) {
            $createPublicDesktopShortcuts = [bool]$config.shortcuts.createPublicDesktopShortcuts
        }

        if ($null -ne $config.shortcuts -and -not [string]::IsNullOrWhiteSpace([string]$config.shortcuts.iconRelativePath)) {
            $configuredIconPath = Join-Path $srcRoot ([string]$config.shortcuts.iconRelativePath)
            if (Test-Path $configuredIconPath) {
                $shortcutIconLocation = $configuredIconPath
            }
            else {
                Write-Host "Warning: Shortcut icon not found at configured path; using default icon. $configuredIconPath" -ForegroundColor DarkYellow
            }
        }
    }
    catch {
        Write-Host "Warning: Unable to parse config; using default shortcut settings. $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}

$shortcutNames = @(
    "CITA Lab Tools.lnk"
)

$legacyShortcutNames = @(
    "CITA Server Setup.lnk"
)

$locations = @(
    [pscustomobject]@{ Label = "CurrentUser Desktop"; Path = [Environment]::GetFolderPath("Desktop") },
    [pscustomobject]@{ Label = "CurrentUser StartMenu"; Path = (Join-Path ([Environment]::GetFolderPath("StartMenu")) "Programs") }
)

if ($isElevated) {
    $locations += [pscustomobject]@{ Label = "AllUsers StartMenu"; Path = (Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs") }
}
else {
    Write-Host "Not elevated: skipping all-users Start Menu shortcut writes." -ForegroundColor DarkYellow
}

if ($createPublicDesktopShortcuts -and $isElevated) {
    $locations += [pscustomobject]@{ Label = "AllUsers Desktop"; Path = [Environment]::GetFolderPath("CommonDesktopDirectory") }
}
elseif ($createPublicDesktopShortcuts -and -not $isElevated) {
    Write-Host "Not elevated: skipping all-users Desktop shortcut writes." -ForegroundColor DarkYellow
}

$created = @()
$failed = @()
$removed = @()

$commonDesktopPath = [Environment]::GetFolderPath("CommonDesktopDirectory")
if ($commonDesktopPath -and -not $createPublicDesktopShortcuts -and $isElevated) {
    foreach ($shortcutName in ($shortcutNames + $legacyShortcutNames)) {
        $publicShortcutPath = Join-Path $commonDesktopPath $shortcutName

        if (-not (Test-Path $publicShortcutPath)) { continue }

        try {
            Remove-Item -Path $publicShortcutPath -Force
            $removed += "[AllUsers Desktop] $publicShortcutPath"
        }
        catch {
            $failed += "[AllUsers Desktop] $publicShortcutPath :: $($_.Exception.Message)"
        }
    }
}
elseif ($commonDesktopPath -and -not $createPublicDesktopShortcuts -and -not $isElevated) {
    Write-Host "Not elevated: skipping public desktop cleanup." -ForegroundColor DarkYellow
}

foreach ($location in $locations) {
    if (-not $location.Path) { continue }

    foreach ($legacyShortcutName in $legacyShortcutNames) {
        $legacyShortcutPath = Join-Path $location.Path $legacyShortcutName

        if (-not (Test-Path $legacyShortcutPath)) { continue }

        try {
            Remove-Item -Path $legacyShortcutPath -Force
            $removed += "[$($location.Label)] $legacyShortcutPath"
        }
        catch {
            $failed += "[$($location.Label)] $legacyShortcutPath :: $($_.Exception.Message)"
        }
    }
}

foreach ($location in $locations) {
    if (-not $location.Path) { continue }

    foreach ($shortcutName in $shortcutNames) {
        $shortcutPath = Join-Path $location.Path $shortcutName

        try {
            New-LabShortcut -ShortcutPath $shortcutPath -LauncherPath $launcherPath -WorkingDirectory $workingDir -IconLocation $shortcutIconLocation
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

Write-Host ""
Write-Host "Public desktop shortcuts enabled: $createPublicDesktopShortcuts" -ForegroundColor Cyan
Write-Host "Shortcut icon: $shortcutIconLocation" -ForegroundColor Cyan

if ($removed.Count -gt 0) {
    Write-Host ""
    Write-Host "Removed public desktop shortcuts:" -ForegroundColor Green
    $removed | ForEach-Object { Write-Host " - $_" }
}

if ($failed.Count -gt 0) {
    Write-Host ""
    Write-Host "Some shortcut writes failed (likely permissions on all-users locations):" -ForegroundColor DarkYellow
    $failed | ForEach-Object { Write-Host " - $_" -ForegroundColor DarkYellow }
}
