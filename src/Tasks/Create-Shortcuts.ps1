# src\Tasks\Create-Shortcuts.ps1
$ErrorActionPreference = "Stop"

$srcRoot = Split-Path -Parent $PSScriptRoot
$launcherPath = Join-Path $srcRoot "Launch-LabTools.ps1"
$configPath = Join-Path $srcRoot "config\labtools.json"

if (-not (Test-Path $launcherPath)) {
    throw "Launcher not found: $launcherPath"
}

function Get-PreferredShortcutHostPath {
    function Get-AppPathDefaultValue {
        param([Parameter(Mandatory=$true)][string]$RegistryPath)

        try {
            $item = Get-Item -Path $RegistryPath -ErrorAction Stop
            $value = $item.GetValue("")
            if (-not [string]::IsNullOrWhiteSpace([string]$value) -and (Test-Path $value)) {
                return [string]$value
            }
        }
        catch {
            return $null
        }

        return $null
    }

    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($pwsh) {
        return $pwsh.Source
    }

    $pwshCandidates = @()

    if ($env:ProgramFiles) {
        $pwshCandidates += @(
            (Join-Path $env:ProgramFiles "PowerShell\7\pwsh.exe"),
            (Join-Path $env:ProgramFiles "PowerShell\7-preview\pwsh.exe")
        )

        $pfPowerShellRoot = Join-Path $env:ProgramFiles "PowerShell"
        if (Test-Path $pfPowerShellRoot) {
            $pwshCandidates += @(Get-ChildItem -Path $pfPowerShellRoot -Directory -ErrorAction SilentlyContinue |
                Sort-Object -Property Name -Descending |
                ForEach-Object { Join-Path $_.FullName "pwsh.exe" })
        }
    }

    if (${env:ProgramFiles(x86)}) {
        $pwshCandidates += (Join-Path ${env:ProgramFiles(x86)} "PowerShell\7\pwsh.exe")
    }

    if ($env:LocalAppData) {
        $pwshCandidates += (Join-Path $env:LocalAppData "Microsoft\WindowsApps\pwsh.exe")
    }

    $pwshCandidates += @(
        (Get-AppPathDefaultValue -RegistryPath "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\pwsh.exe"),
        (Get-AppPathDefaultValue -RegistryPath "Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\pwsh.exe")
    )

    $pwshCandidates = $pwshCandidates | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique

    foreach ($candidate in $pwshCandidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    $winPs = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if ($winPs) {
        return $winPs.Source
    }

    throw "No supported PowerShell executable was found for shortcut target."

}

function Test-IsElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsElevated)) {
    Write-Host "Elevation required to create all-users shortcuts. Prompting for Administrator..." -ForegroundColor Yellow

    $elevatedArgs = "-NoLogo -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $elevatedArgs -WorkingDirectory $PSScriptRoot -Verb RunAs
    exit 0
}

function New-LabShortcut {
    param(
        [Parameter(Mandatory=$true)][string]$ShortcutPath,
        [Parameter(Mandatory=$true)][string]$LauncherPath,
        [Parameter(Mandatory=$true)][string]$HostExecutablePath,
        [Parameter(Mandatory=$true)][string]$WorkingDirectory,
        [Parameter(Mandatory=$true)][string]$IconLocation
    )

    $shortcutDir = Split-Path -Parent $ShortcutPath
    if (-not (Test-Path $shortcutDir)) {
        New-Item -Path $shortcutDir -ItemType Directory -Force | Out-Null
    }

    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut($ShortcutPath)

    $shortcut.TargetPath = $HostExecutablePath
    $escapedHostPath = $HostExecutablePath.Replace("'", "''")
    $escapedLauncherPath = $LauncherPath.Replace("'", "''")
    $escapedWorkingDirectory = $WorkingDirectory.Replace("'", "''")

    $elevationWrapper = @"
`$hostExe = '$escapedHostPath'
`$launcher = '$escapedLauncherPath'
`$workingDir = '$escapedWorkingDirectory'
Start-Process -FilePath `$hostExe -ArgumentList @('-NoLogo', '-ExecutionPolicy', 'Bypass', '-File', `$launcher) -WorkingDirectory `$workingDir -Verb RunAs
"@

    $encodedWrapper = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($elevationWrapper))
    $launcherArgs = "-NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encodedWrapper"
    $shortcut.Arguments = $launcherArgs
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.WindowStyle = 1
    $shortcut.Description = "Launch CITA Lab Tools (PowerShell 7 preferred)"
    $shortcut.IconLocation = $IconLocation
    $shortcut.Save()
}

$workingDir = $srcRoot
$preferredHostPath = Get-PreferredShortcutHostPath
$createPublicDesktopShortcuts = $true
$defaultIconLocation = "$preferredHostPath,0"
$shortcutIconLocation = $defaultIconLocation
$isElevated = Test-IsElevated

Write-Host "Shortcut host selected: $preferredHostPath" -ForegroundColor Cyan
if ($preferredHostPath -match '\\WindowsPowerShell\\v1\.0\\powershell\.exe$') {
    Write-Host "Warning: PowerShell 7 was not discovered. Shortcut will use Windows PowerShell." -ForegroundColor DarkYellow
}

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

$preferPublicDesktopShortcut = $createPublicDesktopShortcuts -and $isElevated

$locations = @(
    [pscustomobject]@{ Label = "CurrentUser StartMenu"; Path = (Join-Path ([Environment]::GetFolderPath("StartMenu")) "Programs") }
)

if (-not $preferPublicDesktopShortcut) {
    $locations += [pscustomobject]@{ Label = "CurrentUser Desktop"; Path = [Environment]::GetFolderPath("Desktop") }
}
else {
    Write-Host "Public Desktop shortcut is enabled; skipping current-user Desktop shortcut creation." -ForegroundColor Cyan
}

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

$currentUserDesktopPath = [Environment]::GetFolderPath("Desktop")
$publicDesktopHasManagedShortcut = $false

if ($commonDesktopPath) {
    foreach ($shortcutName in $shortcutNames) {
        $publicShortcutPath = Join-Path $commonDesktopPath $shortcutName
        if (Test-Path $publicShortcutPath) {
            $publicDesktopHasManagedShortcut = $true
            break
        }
    }
}

if ($publicDesktopHasManagedShortcut -and $currentUserDesktopPath) {
    foreach ($shortcutName in ($shortcutNames + $legacyShortcutNames)) {
        $userDesktopShortcutPath = Join-Path $currentUserDesktopPath $shortcutName

        if (-not (Test-Path $userDesktopShortcutPath)) { continue }

        try {
            Remove-Item -Path $userDesktopShortcutPath -Force
            $removed += "[CurrentUser Desktop] $userDesktopShortcutPath (deduped; Public Desktop shortcut exists)"
        }
        catch {
            $failed += "[CurrentUser Desktop] $userDesktopShortcutPath :: $($_.Exception.Message)"
        }
    }
}

foreach ($location in $locations) {
    if (-not $location.Path) { continue }

    foreach ($shortcutName in $shortcutNames) {
        $shortcutPath = Join-Path $location.Path $shortcutName

        try {
            New-LabShortcut -ShortcutPath $shortcutPath -LauncherPath $launcherPath -HostExecutablePath $preferredHostPath -WorkingDirectory $workingDir -IconLocation $shortcutIconLocation
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
    Write-Host "Removed shortcuts:" -ForegroundColor Green
    $removed | ForEach-Object { Write-Host " - $_" }
}

if ($failed.Count -gt 0) {
    Write-Host ""
    Write-Host "Some shortcut writes failed (likely permissions on all-users locations):" -ForegroundColor DarkYellow
    $failed | ForEach-Object { Write-Host " - $_" -ForegroundColor DarkYellow }
}
